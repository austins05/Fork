//
//  NavigationManager.swift
//  Rotorsync
//
//  Created on 11/15/25.
//

import Foundation
import MapKit
import Combine
import AVFoundation

class NavigationManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var status: NavigationStatus = .idle
    @Published var availableRoutes: [NavigationRoute] = []
    @Published var selectedRoute: NavigationRoute?
    @Published var currentStepIndex: Int = 0
    @Published var remainingDistance: Double = 0 // meters
    @Published var remainingTime: TimeInterval = 0 // seconds
    @Published var nextStep: NavigationStep?
    @Published var currentStep: NavigationStep?
    @Published var distanceToNextStep: Double = 0
    @Published var voiceGuidanceEnabled: Bool = true
    @Published var waypoints: [CLLocationCoordinate2D] = []
    @Published var remainingRoutePolyline: MKPolyline? // Only the portion ahead of user

    // MARK: - Properties
    private let locationManager: LocationManager
    private var fullRoutePolyline: MKPolyline? // Complete route for reference
    private var settings = NavigationSettings.load()
    private var cancellables = Set<AnyCancellable>()
    private var routeSteps: [NavigationStep] = []
    var destination: CLLocationCoordinate2D? // Made public for recalculation
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var lastAnnouncedDistance: Double?
    private let offRouteThreshold: CLLocationDistance = 150 // meters (increased from 50 for less false positives)
    private var consecutiveOffRouteCount = 0
    private var lastRerouteTime: Date?
    private var lastTrimmedIndex = 0  // Cache for route trimming optimization
    private var lastTrimTime: Date?  // Throttle route trimming

    // Voice announcement distances (in meters)
    private let announcementDistances: [Double] = [804.672, 402.336, 161.3344, 30.48] // 2640ft, 1320ft, 529ft, 100ft

    // MARK: - Initialization
    init(locationManager: LocationManager) {
        self.locationManager = locationManager
        super.init()
        self.voiceGuidanceEnabled = settings.voiceGuidanceEnabled
        setupLocationTracking()
    }

    // MARK: - Route Calculation
    func calculateRoutes(to destination: CLLocationCoordinate2D) {
        print("🧭 [NAV MANAGER] calculateRoutes called")
        print("🧭 [NAV MANAGER] Destination: \(destination.latitude), \(destination.longitude)")
        print("🧭 [NAV MANAGER] Waypoints: \(waypoints.count)")
        self.destination = destination
        status = .calculatingRoute
        print("🧭 [NAV MANAGER] Status set to: calculatingRoute")

        // Reload settings to get latest preferences
        settings = NavigationSettings.load()
        print("🧭 [NAV MANAGER] Settings loaded - avoidHighways: \(settings.avoidHighways)")

        guard let userLocation = locationManager.userLocation else {
            print("❌ [NAV MANAGER] No user location available")
            status = .error("Unable to get current location")
            return
        }
        print("🧭 [NAV MANAGER] User location: \(userLocation.coordinate.latitude), \(userLocation.coordinate.longitude)")

        // If waypoints exist, use chained routing
        if !waypoints.isEmpty {
            print("🧭 [NAV MANAGER] Using waypoint routing with \(waypoints.count) waypoints")
            calculateRoutesWithWaypoints(from: userLocation.coordinate, to: destination)
            return
        }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: userLocation.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        request.requestsAlternateRoutes = true

        // Apply highway avoidance if enabled
        if settings.avoidHighways {
            request.highwayPreference = .avoid
        }

        let directions = MKDirections(request: request)

        directions.calculate { [weak self] response, error in
            guard let self = self else {
                print("❌ [NAV MANAGER] Self was deallocated")
                return
            }

            if let error = error {
                print("❌ [NAV MANAGER] Route calculation failed: \(error.localizedDescription)")
                self.status = .error("Failed to calculate route: \(error.localizedDescription)")
                return
            }

            guard let response = response, !response.routes.isEmpty else {
                print("❌ [NAV MANAGER] No routes found in response")
                self.status = .error("No routes found")
                return
            }

            print("✅ [NAV MANAGER] Found \(response.routes.count) routes")

            // Convert to NavigationRoute objects
            let navRoutes = response.routes.enumerated().map { index, route in
                let name = index == 0 ? "Fastest Route" : "Alternate Route \(index)"
                print("🧭 [NAV MANAGER] Route \(index): \(name) - \(route.distance/1609.34) mi, \(route.expectedTravelTime/60) min")
                return NavigationRoute(
                    route: route,
                    name: name,
                    distance: route.distance,
                    expectedTravelTime: route.expectedTravelTime,
                    combinedPolyline: nil,
                    routeSegments: nil
                )
            }

            self.availableRoutes = navRoutes
            self.status = .selectingRoute(navRoutes)
            print("✅ [NAV MANAGER] Status set to: selectingRoute with \(navRoutes.count) routes")
        }
    }

    // MARK: - Waypoint Management
    func addWaypoint(_ coordinate: CLLocationCoordinate2D) {
        print("📍 [WAYPOINT] Adding waypoint at: \(coordinate.latitude), \(coordinate.longitude)")

        // Fix #4: Check waypoint limit
        guard waypoints.count < 5 else {
            print("⚠️ [WAYPOINT] Maximum 5 waypoints allowed")
            status = .error("Maximum 5 waypoints allowed")
            return
        }

        // Fix #3: Check for duplicates within 50m
        let tooClose = waypoints.contains { existing in
            let existingLoc = CLLocation(latitude: existing.latitude, longitude: existing.longitude)
            let newLoc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let dist = existingLoc.distance(from: newLoc)
            return dist < 50
        }
        
        if tooClose {
            print("⚠️ [WAYPOINT] Waypoint too close to existing waypoint - ignoring")
            status = .error("Waypoint too close to existing waypoint (minimum 50m separation)")
            return
        }

        // Add waypoint
        waypoints.append(coordinate)
        print("📍 [WAYPOINT] Total waypoints: \(waypoints.count)")

        // Recalculate routes with new waypoint
        if let dest = destination {
            print("📍 [WAYPOINT] Triggering recalculation to: \(dest.latitude), \(dest.longitude)")
            calculateRoutes(to: dest)
        } else {
            print("❌ [WAYPOINT] No destination set!")
        }
    }

    func removeWaypoint(at index: Int) {
        guard index < waypoints.count else { return }
        print("📍 [WAYPOINT] Removing waypoint \(index + 1)")
        waypoints.remove(at: index)

        // Recalculate routes without this waypoint
        if let dest = destination {
            calculateRoutes(to: dest)
        }
    }

    func clearWaypoints() {
        print("📍 [WAYPOINT] Clearing all waypoints")
        waypoints.removeAll()
    }

    // MARK: - Multi-Segment Route Calculation
    private func calculateRoutesWithWaypoints(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) {
        print("🧭 [WAYPOINT ROUTING] Calculating route with \(waypoints.count) waypoints")

        // Auto-sort waypoints for efficient routing
        sortWaypointsAlongPath(from: origin, to: destination)
    }

    private func sortWaypointsAlongPath(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) {
        guard !waypoints.isEmpty else {
            calculateSegmentedRoute(from: origin, waypoints: [], to: destination)
            return
        }

        print("🔄 [WAYPOINT SORT] Sorting \(waypoints.count) waypoints for optimal order")

        // Calculate direct route to find natural path
        let directRequest = MKDirections.Request()
        directRequest.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        directRequest.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        directRequest.transportType = .automobile
        directRequest.requestsAlternateRoutes = false

        if settings.avoidHighways {
            directRequest.highwayPreference = .avoid
        }

        MKDirections(request: directRequest).calculate { [weak self] response, error in
            guard let self = self, let directRoute = response?.routes.first else {
                print("⚠️ [WAYPOINT SORT] Direct route failed, using waypoint order as-is")
                self?.calculateSegmentedRoute(from: origin, waypoints: self?.waypoints ?? [], to: destination)
                return
            }

            // Find position of each waypoint along the route
            var waypointPositions: [(waypoint: CLLocationCoordinate2D, distanceAlongRoute: Double)] = []

            for waypoint in self.waypoints {
                let (closestPoint, distanceAlong) = self.findPositionAlongRoute(for: waypoint, route: directRoute)
                waypointPositions.append((waypoint: waypoint, distanceAlongRoute: distanceAlong))
                print("📍 [WAYPOINT SORT] Waypoint at \(waypoint.latitude), \(waypoint.longitude) → \(distanceAlong/1609.34) mi along route")
            }

            // Sort waypoints by their position along the route (closest to origin first)
            waypointPositions.sort { $0.distanceAlongRoute < $1.distanceAlongRoute }

            let sortedWaypoints = waypointPositions.map { $0.waypoint }

            print("🔄 [WAYPOINT SORT] Sorted waypoints:")
            for (i, wp) in sortedWaypoints.enumerated() {
                print("   \(i+1). \(wp.latitude), \(wp.longitude)")
            }

            // Update the waypoints array with sorted order
            self.waypoints = sortedWaypoints

            // Calculate route through sorted waypoints
            self.calculateSegmentedRoute(from: origin, waypoints: sortedWaypoints, to: destination)
        }
    }

    private func findPositionAlongRoute(for waypoint: CLLocationCoordinate2D, route: MKRoute) -> (closestPoint: CLLocationCoordinate2D, distanceAlongRoute: Double) {
        let waypointLocation = CLLocation(latitude: waypoint.latitude, longitude: waypoint.longitude)
        let points = route.polyline.points()
        let count = route.polyline.pointCount

        var closestIndex = 0
        var minDistance: CLLocationDistance = .greatestFiniteMagnitude

        // Find closest point on route
        for i in 0..<count {
            let pointCoord = points[i].coordinate
            let pointLocation = CLLocation(latitude: pointCoord.latitude, longitude: pointCoord.longitude)
            let distance = waypointLocation.distance(from: pointLocation)

            if distance < minDistance {
                minDistance = distance
                closestIndex = i
            }
        }

        // Calculate distance along route to this point
        var distanceAlongRoute: Double = 0
        for i in 0..<closestIndex {
            if i + 1 < count {
                let coord1 = points[i].coordinate
                let coord2 = points[i + 1].coordinate
                let loc1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
                let loc2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
                distanceAlongRoute += loc1.distance(from: loc2)
            }
        }

        return (points[closestIndex].coordinate, distanceAlongRoute)
    }

    // Fix #1: Remove infinite recursion - add retryCount parameter with guard
    private func calculateSegmentedRoute(from origin: CLLocationCoordinate2D, waypoints: [CLLocationCoordinate2D], to destination: CLLocationCoordinate2D, retryCount: Int = 0) {
        // Guard against infinite recursion
        guard retryCount < 3 else {
            print("❌ [WAYPOINT ROUTING] Max retry attempts reached (\(retryCount))")
            status = .error("Failed to calculate route after \(retryCount) attempts")
            return
        }
        
        // Build coordinate chain: origin → waypoint1 → waypoint2 → ... → destination
        var coordinates = [origin] + waypoints + [destination]
        print("🧭 [WAYPOINT ROUTING] Total segments: \(coordinates.count - 1) (Attempt \(retryCount + 1)/3)")
        print("🧭 [WAYPOINT ROUTING] Origin: \(origin.latitude), \(origin.longitude)")
        for (i, wp) in waypoints.enumerated() {
            print("🧭 [WAYPOINT ROUTING] Waypoint \(i+1): \(wp.latitude), \(wp.longitude)")
        }
        print("🧭 [WAYPOINT ROUTING] Destination: \(destination.latitude), \(destination.longitude)")

        var allSegmentRoutes: [[MKRoute]] = Array(repeating: [], count: coordinates.count - 1)
        let dispatchGroup = DispatchGroup()
        var failedSegments: [(Int, Error)] = []  // Fix #2: Track failed segments

        // Calculate each segment
        for i in 0..<(coordinates.count - 1) {
            dispatchGroup.enter()

            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: coordinates[i]))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinates[i + 1]))
            request.transportType = .automobile
            request.requestsAlternateRoutes = true

            if settings.avoidHighways {
                request.highwayPreference = .avoid
            }

            let fromCoord = coordinates[i]
            let toCoord = coordinates[i + 1]
            print("🧭 [WAYPOINT ROUTING] Segment \(i + 1): FROM (\(fromCoord.latitude), \(fromCoord.longitude)) TO (\(toCoord.latitude), \(toCoord.longitude))")

            MKDirections(request: request).calculate { response, error in
                defer { dispatchGroup.leave() }

                if let error = error {
                    print("❌ [WAYPOINT ROUTING] Segment \(i + 1) failed: \(error.localizedDescription)")
                    failedSegments.append((i, error))  // Fix #2: Collect errors
                    return
                }

                if let routes = response?.routes, !routes.isEmpty {
                    print("✅ [WAYPOINT ROUTING] Segment \(i + 1) calculated: \(routes.count) route options")
                    for (idx, route) in routes.enumerated() {
                        print("   Route \(idx + 1): \(route.distance/1609.34) mi")
                    }
                    allSegmentRoutes[i] = routes
                }
            }
        }

        // Wait for all segments to complete
        dispatchGroup.notify(queue: .main) { [weak self] in
            guard let self = self else { return }

            // Fix #2: Handle failed segments with retry logic
            if !failedSegments.isEmpty {
                print("❌ [WAYPOINT ROUTING] Failed segments: \(failedSegments.count)/\(coordinates.count - 1)")
                
                // If all segments failed, show error
                if failedSegments.count == coordinates.count - 1 {
                    self.status = .error("Route calculation failed for all segments")
                    return
                }
                
                // Retry with delay (Fix #1: increment retry counter)
                print("🔄 [WAYPOINT ROUTING] Retrying in 1 second (attempt \(retryCount + 2)/3)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.calculateSegmentedRoute(from: origin, waypoints: waypoints, to: destination, retryCount: retryCount + 1)
                }
                return
            }

            // Combine segments into complete route
            self.combineRouteSegments(allSegmentRoutes)
        }
    }

    private func combineRouteSegments(_ segmentRoutes: [[MKRoute]]) {
        print("🧭 [WAYPOINT ROUTING] Combining \(segmentRoutes.count) route segments")

        guard !segmentRoutes.isEmpty, segmentRoutes.allSatisfy({ !$0.isEmpty }) else {
            print("❌ [WAYPOINT ROUTING] Missing route segments")
            status = .error("Could not complete route calculation")
            return
        }

        // Create up to 3 route combinations from segment alternates
        var combinedRoutes: [NavigationRoute] = []

        // Combination 1: Fastest route for each segment
        let fastestCombo = segmentRoutes.map { $0.first! }
        if let route1 = createCombinedRoute(from: fastestCombo, name: "Fastest Route") {
            combinedRoutes.append(route1)
        }

        // Combination 2: Use second route option for first segment if available
        if segmentRoutes[0].count > 1 {
            var combo2 = segmentRoutes.map { $0.first! }
            combo2[0] = segmentRoutes[0][1]
            if let route2 = createCombinedRoute(from: combo2, name: "Alternate Route 1") {
                combinedRoutes.append(route2)
            }
        }

        // Combination 3: Use second route for last segment if available and multi-segment
        if segmentRoutes.count > 1, segmentRoutes[segmentRoutes.count - 1].count > 1 {
            var combo3 = segmentRoutes.map { $0.first! }
            combo3[segmentRoutes.count - 1] = segmentRoutes[segmentRoutes.count - 1][1]
            if let route3 = createCombinedRoute(from: combo3, name: "Alternate Route 2") {
                combinedRoutes.append(route3)
            }
        }

        print("✅ [WAYPOINT ROUTING] Created \(combinedRoutes.count) route options")

        availableRoutes = combinedRoutes
        status = .selectingRoute(combinedRoutes)
    }

    private func createCombinedRoute(from segments: [MKRoute], name: String) -> NavigationRoute? {
        guard !segments.isEmpty else { return nil }

        // Combine all polylines
        var allCoordinates: [CLLocationCoordinate2D] = []
        for route in segments {
            let points = route.polyline.points()
            for i in 0..<route.polyline.pointCount {
                allCoordinates.append(points[i].coordinate)
            }
        }

        // Create combined polyline
        let combinedPolyline = MKPolyline(coordinates: allCoordinates, count: allCoordinates.count)

        // Calculate total distance and time
        let totalDistance = segments.reduce(0.0) { $0 + $1.distance }
        let totalTime = segments.reduce(0.0) { $0 + $1.expectedTravelTime }

        print("✅ [WAYPOINT ROUTING] \(name): \(totalDistance/1609.34) mi, \(totalTime/60) min")

        return NavigationRoute(
            route: segments[0],
            name: name,
            distance: totalDistance,
            expectedTravelTime: totalTime,
            combinedPolyline: combinedPolyline,
            routeSegments: segments
        )
    }

    // MARK: - Start Navigation
    func startNavigation(with route: NavigationRoute) {
        print("🧭 [NAV START] startNavigation called")
        selectedRoute = route

        // Store full route polyline for trimming as user progresses
        fullRoutePolyline = route.combinedPolyline ?? route.route.polyline
        remainingRoutePolyline = fullRoutePolyline // Start with full route

        // Handle waypoint routes specially - combine all segment steps
        if let segments = route.routeSegments, !segments.isEmpty {
            print("🧭 [NAV START] Using \(segments.count) route segments for waypoint route")
            prepareStepsFromSegments(segments, totalDistance: route.distance, totalTime: route.expectedTravelTime)
        } else {
            print("🧭 [NAV START] Using single route with \(route.route.steps.count) steps")
            prepareSteps(from: route.route)
        }

        print("🧭 [NAV START] Prepared \(routeSteps.count) total steps")

        // Debug: Print all steps
        for (index, step) in routeSteps.enumerated() {
            print("🧭 [STEP \(index)] \(step.instruction) - Distance: \(step.distance)m")
        }

        currentStepIndex = 0
        lastTrimmedIndex = 0  // Reset route trimming cache
        lastTrimTime = nil  // Reset throttle
        updateCurrentAndNextSteps()
        status = .navigating
        print("🧭 [NAV START] Status set to: navigating")
        print("🧭 [NAV START] First instruction: \(currentStep?.instruction ?? "none")")

        // Configure audio session for voice guidance
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)
            print("🔊 [AUDIO SESSION] Successfully configured for voice guidance")
        } catch {
            print("⚠️ [AUDIO SESSION] Failed to configure: \(error.localizedDescription)")
        }

        print("🧭 [NAV START] Current step: \(currentStep?.instruction ?? "none")")

        // Announce start
        if voiceGuidanceEnabled {
            speak("Navigation started. \(route.distanceString) to destination.")
        }
    }

    // MARK: - Stop Navigation
    func stopNavigation() {
        print("🛑 [NAV STOP] stopNavigation called")
        print("🛑 [NAV STOP] Previous status: \(status)")
        status = .idle
        selectedRoute = nil
        routeSteps = []
        currentStepIndex = 0
        currentStep = nil
        nextStep = nil
        remainingDistance = 0
        remainingTime = 0
        distanceToNextStep = 0
        lastAnnouncedDistance = nil
        consecutiveOffRouteCount = 0
        lastTrimmedIndex = 0  // Reset trim cache
        lastTrimTime = nil  // Reset trim throttle
        fullRoutePolyline = nil
        remainingRoutePolyline = nil
        speechSynthesizer.stopSpeaking(at: .immediate)
        print("🛑 [NAV STOP] Navigation stopped, status now: idle")
    }

    // MARK: - Private Methods
    private func setupLocationTracking() {
        locationManager.$userLocation
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                self?.updateNavigationProgress(with: location)
            }
            .store(in: &cancellables)
    }

    private func prepareSteps(from route: MKRoute) {
        routeSteps = route.steps.map { step in
            NavigationStep(
                instruction: step.instructions,
                distance: step.distance,
                polyline: step.polyline,
                notice: step.notice
            )
        }

        remainingDistance = route.distance
        remainingTime = route.expectedTravelTime
    }

    private func prepareStepsFromSegments(_ segments: [MKRoute], totalDistance: Double, totalTime: TimeInterval) {
        print("🧭 [NAV START] Combining steps from \(segments.count) segments")

        // Combine all steps from all segments
        var allSteps: [NavigationStep] = []

        for (segmentIndex, segment) in segments.enumerated() {
            print("🧭 [NAV START] Segment \(segmentIndex + 1) has \(segment.steps.count) steps")

            let segmentSteps = segment.steps.map { step in
                NavigationStep(
                    instruction: step.instructions,
                    distance: step.distance,
                    polyline: step.polyline,
                    notice: step.notice
                )
            }

            allSteps.append(contentsOf: segmentSteps)
        }

        routeSteps = allSteps
        remainingDistance = totalDistance
        remainingTime = totalTime

        print("🧭 [NAV START] Total combined steps: \(allSteps.count)")
    }

    private func updateCurrentAndNextSteps() {
        guard currentStepIndex < routeSteps.count else {
            currentStep = nil
            nextStep = nil
            return
        }

        currentStep = routeSteps[currentStepIndex]

        if currentStepIndex + 1 < routeSteps.count {
            nextStep = routeSteps[currentStepIndex + 1]
        } else {
            nextStep = nil
        }
    }

    private func updateNavigationProgress(with location: CLLocation) {
        guard status == .navigating || status == .rerouting,
              let route = selectedRoute,
              currentStepIndex < routeSteps.count else {
            print("🔊 [NAV PROGRESS] Not updating - status: \(status), stepIndex: \(currentStepIndex)/\(routeSteps.count)")
            return
        }

        // Don't update if user is stationary or barely moving (< 1.0 m/s or ~2 mph)
        // This prevents false announcements when GPS jitters while parked
        // Note: speed < 0 means invalid, so we check for valid speed that's too slow
        if location.speed >= 0 && location.speed < 1.0 {
            print("🔊 [NAV PROGRESS] Skipping update - user stationary/slow (speed: \(location.speed) m/s)")
            return
        }

        // Also skip if speed is invalid
        if location.speed < 0 {
            print("🔊 [NAV PROGRESS] Skipping update - invalid speed data (\(location.speed))")
            return
        }

        let currentLocation = location.coordinate
        let currentStepCoordinate = getStepCoordinate(at: currentStepIndex)

        // Calculate distance to current step
        let stepLocation = CLLocation(latitude: currentStepCoordinate.latitude, longitude: currentStepCoordinate.longitude)
        distanceToNextStep = location.distance(from: stepLocation)

        let stepInstruction = currentStep?.instruction ?? "none"
        let distanceMiles = distanceToNextStep / 1609.34
        print("🔊 [NAV PROGRESS] Step \(currentStepIndex + 1)/\(routeSteps.count): '\(stepInstruction)'")
        print("🔊 [NAV PROGRESS] Distance to maneuver: \(distanceToNextStep)m (\(distanceToNextStep * 3.28084)ft / \(String(format: "%.2f", distanceMiles))mi)")
        print("🔊 [NAV PROGRESS] Speed: \(location.speed)m/s, Coord: \(currentLocation.latitude), \(currentLocation.longitude)")

        // Update remaining route polyline (trim traveled portion)
        trimRoutePolyline(userLocation: location)

        // Check if we should advance to next step (within 20 meters of maneuver point)
        // Conservative threshold to prevent premature advancement
        if distanceToNextStep < 20 {
            let nextInstruction = (currentStepIndex + 1 < routeSteps.count) ? routeSteps[currentStepIndex + 1].instruction : "destination"
            print("⏭️  [STEP ADVANCE] Distance < 20m (\(distanceToNextStep)m), advancing from step \(currentStepIndex + 1) to \(currentStepIndex + 2)")
            print("⏭️  [STEP ADVANCE] Leaving: '\(currentStep?.instruction ?? "")' → Going to: '\(nextInstruction)'")
            advanceToNextStep()
        }

        // Update remaining distance and time
        updateRemainingStats(from: location)

        // Check if off route
        if isOffRoute(location: location) {
            consecutiveOffRouteCount += 1
            print("⚠️ [OFF ROUTE] Off route detected - count: \(consecutiveOffRouteCount)/5")
            if consecutiveOffRouteCount >= 5 { // 5 consecutive readings to avoid false positives
                print("🔴 [OFF ROUTE] Triggering reroute after 5 consecutive readings")
                handleOffRoute()
            }
        } else {
            if consecutiveOffRouteCount > 0 {
                print("✅ [ON ROUTE] Back on route - resetting counter")
            }
            consecutiveOffRouteCount = 0
        }

        // Voice guidance - use published property
        print("🔊 [NAV PROGRESS] Voice check - enabled: \(voiceGuidanceEnabled), distance: \(distanceToNextStep)m")
        if voiceGuidanceEnabled {
            announceIfNeeded(distanceToStep: distanceToNextStep)
        } else {
            print("⚠️ [NAV PROGRESS] Voice guidance disabled - skipping announcement")
        }

        // Check if arrived at final destination
        if let dest = destination {
            let destLocation = CLLocation(latitude: dest.latitude, longitude: dest.longitude)
            let distanceToDestination = location.distance(from: destLocation)

            // Only check for arrival if on the last step
            if currentStepIndex >= routeSteps.count - 1 {
                print("🎯 [ARRIVAL CHECK] On final step, distance to destination: \(distanceToDestination)m")
                if distanceToDestination < 30 { // Within 30 meters (~100 ft)
                    print("🎯 [ARRIVED] Within 30m of destination!")
                    arriveAtDestination()
                }
            }
        }
    }

    private func getStepCoordinate(at index: Int) -> CLLocationCoordinate2D {
        guard index < routeSteps.count else {
            return destination ?? CLLocationCoordinate2D()
        }

        let step = routeSteps[index]
        let points = step.polyline.points()
        let count = step.polyline.pointCount

        // CRITICAL FIX: Use LAST coordinate (end of step/where maneuver happens)
        // The first coordinate is often where you currently are, causing immediate advancement
        // The last coordinate is where you actually need to perform the maneuver
        if count > 0 {
            let maneuverCoord = points[count - 1].coordinate
            print("📍 [GET COORD] Step \(index): '\(step.instruction)' - Using END of polyline (\(count) points total)")
            return maneuverCoord
        }

        return destination ?? CLLocationCoordinate2D()
    }

    private func advanceToNextStep() {
        print("⏭️  [ADVANCE] Advancing from step \(currentStepIndex) to \(currentStepIndex + 1)")
        currentStepIndex += 1
        updateCurrentAndNextSteps()
        lastAnnouncedDistance = nil // Reset for next step
        print("⏭️  [ADVANCE] New current step: '\(currentStep?.instruction ?? "none")'")

        if let instruction = currentStep?.instruction, !instruction.isEmpty {
            print("⏭️  [ADVANCE] Speaking new step instruction: '\(instruction)'")
            if voiceGuidanceEnabled {
                speak(instruction)
            }
        } else {
            print("⏭️  [ADVANCE] No instruction to speak for new step")
        }
    }

    private func updateRemainingStats(from location: CLLocation) {
        guard let route = selectedRoute else { return }

        // Calculate remaining distance (simple approximation)
        var distance: Double = 0
        for i in currentStepIndex..<routeSteps.count {
            distance += routeSteps[i].distance
        }
        distance += distanceToNextStep

        remainingDistance = distance

        // Estimate remaining time based on current speed
        if let speed = locationManager.userLocation?.speed, speed > 0 {
            remainingTime = distance / speed
        } else {
            // Fallback to original estimate
            let progress = 1.0 - (distance / route.distance)
            remainingTime = route.expectedTravelTime * (1.0 - progress)
        }
    }

    private func isOffRoute(location: CLLocation) -> Bool {
        guard currentStepIndex < routeSteps.count else { return false }

        let step = routeSteps[currentStepIndex]
        let polyline = step.polyline

        // Check distance to polyline
        let distance = distanceToPolyline(from: location.coordinate, polyline: polyline)
        let isOff = distance > offRouteThreshold

        if isOff {
            print("⚠️ [OFF ROUTE CHECK] Distance from route: \(distance)m (threshold: \(offRouteThreshold)m)")
        }

        return isOff
    }

    private func distanceToPolyline(from coordinate: CLLocationCoordinate2D, polyline: MKPolyline) -> CLLocationDistance {
        let points = polyline.points()
        let count = polyline.pointCount

        var minDistance = CLLocationDistance.greatestFiniteMagnitude

        let userLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        for i in 0..<count {
            let pointCoord = points[i].coordinate
            let pointLocation = CLLocation(latitude: pointCoord.latitude, longitude: pointCoord.longitude)
            let distance = userLocation.distance(from: pointLocation)

            if distance < minDistance {
                minDistance = distance
            }
        }

        return minDistance
    }

    private func handleOffRoute() {
        // Throttle rerouting (max once per 10 seconds)
        if let lastReroute = lastRerouteTime, Date().timeIntervalSince(lastReroute) < 10 {
            print("⏱️ [REROUTE] Skipping reroute - too soon since last attempt")
            return
        }

        lastRerouteTime = Date()
        print("🔄 [REROUTE] User is off route - recalculating")
        status = .rerouting

        if let dest = destination {
            calculateRoutes(to: dest)
        }
    }

    private func arriveAtDestination() {
        print("🎯 [NAV] Arrived at destination!")
        status = .arrived
        speechSynthesizer.stopSpeaking(at: .immediate)

        if voiceGuidanceEnabled {
            speak("You have arrived at your destination.")
        }
    }

    private func announceIfNeeded(distanceToStep distance: Double) {
        print("📢 [ANNOUNCE DEBUG] ========================================")
        print("📢 [ANNOUNCE DEBUG] Called with distance: \(distance)m (\(distance * 3.28084)ft)")
        let stepText = currentStep?.instruction ?? "nil"
        print("📢 [ANNOUNCE DEBUG] Current step: \(stepText)")
        let lastDistText = lastAnnouncedDistance?.description ?? "nil"
        print("📢 [ANNOUNCE DEBUG] Last announced distance: \(lastDistText)")
        print("📢 [ANNOUNCE DEBUG] Announcement thresholds: \(announcementDistances)")

        // Sanity check: Don't announce if distance is unreasonably far (> 1 mile = 1609m)
        // This prevents incorrect announcements from GPS errors or wrong calculations
        if distance > 1609 {
            print("📢 [ANNOUNCE DEBUG] Distance too far (\(distance)m) - skipping announcement")
            print("📢 [ANNOUNCE DEBUG] ========================================")
            return
        }

        // CRITICAL FIX: If this is the first check (lastAnnouncedDistance is nil),
        // initialize it to current distance instead of announcing immediately.
        // This prevents "turn in 308 ft" when you're 1.5 miles away and haven't moved yet.
        if lastAnnouncedDistance == nil {
            lastAnnouncedDistance = distance
            print("📢 [ANNOUNCE DEBUG] First check - initializing lastAnnouncedDistance to \(distance)m")
            print("📢 [ANNOUNCE DEBUG] Will announce when user crosses thresholds while moving")
            print("📢 [ANNOUNCE DEBUG] ========================================")
            return
        }

        print("📢 [ANNOUNCE DEBUG] ========================================")

        for threshold in announcementDistances {
            // Only announce when crossing threshold (from far to near)
            let shouldAnnounce = lastAnnouncedDistance! > threshold && distance <= threshold
            print("📢 [ANNOUNCE DEBUG] Threshold \(threshold)m: lastDist=\(lastAnnouncedDistance!), currDist=\(distance), shouldAnnounce=\(shouldAnnounce)")

            if shouldAnnounce {
                print("🔊 [VOICE] Threshold crossed: \(threshold)m")
                if let instruction = currentStep?.instruction {
                    let distanceInFeet = Int(distance * 3.28084)
                    let announcement = "In \(distanceInFeet) feet, \(instruction)"
                    print("🔊 [VOICE] Speaking: \(announcement)")
                    speak(announcement)
                    lastAnnouncedDistance = distance
                } else {
                    print("⚠️ [VOICE] No instruction available")
                }
                return
            }
        }

        // Update last distance even if no announcement (for next comparison)
        if distance < lastAnnouncedDistance! {
            lastAnnouncedDistance = distance
            print("📢 [ANNOUNCE DEBUG] Updated lastAnnouncedDistance to \(distance)m (getting closer)")
        }

        print("🔊 [VOICE] No threshold crossed")
    }

    private func speak(_ text: String) {
        print("🔊 [VOICE DEBUG] ========================================")
        print("🔊 [VOICE DEBUG] speak() called with: \(text)")
        print("🔊 [VOICE DEBUG] voiceGuidanceEnabled: \(voiceGuidanceEnabled)")
        print("🔊 [VOICE DEBUG] Synthesizer speaking: \(speechSynthesizer.isSpeaking)")
        
        // Check audio session status
        let session = AVAudioSession.sharedInstance()
        print("🔊 [VOICE DEBUG] Audio session category: \(session.category.rawValue)")
        print("🔊 [VOICE DEBUG] Audio session active: \(session.isOtherAudioPlaying)")
        print("🔊 [VOICE DEBUG] ========================================")

        guard voiceGuidanceEnabled else {
            print("⚠️ [VOICE] Voice guidance disabled - not speaking")
            return
        }

        speechSynthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)

        // Select highest quality voice available - check ALL English variants
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let englishVoices = allVoices.filter { $0.language.hasPrefix("en") }

        // Debug: Print ALL available English voices with their quality
        print("🔊 [VOICE DEBUG] === ALL ENGLISH VOICES ===")
        for voice in englishVoices {
            print("🔊 [VOICE OPTION] \(voice.name) - Quality: \(voice.quality.rawValue) - Lang: \(voice.language) - ID: \(voice.identifier)")
        }
        print("🔊 [VOICE DEBUG] =============================")

        // Look for premium voices
        let premiumVoices = englishVoices.filter { $0.quality == .premium }
        print("🔊 [VOICE DEBUG] Found \(premiumVoices.count) premium voices")
        for voice in premiumVoices {
            print("🔊 [PREMIUM] \(voice.name) - Lang: \(voice.language) - \(voice.identifier)")
        }

        // Select premium quality voice (highest quality available)
        // Priority: any premium voice > enhanced > US default
        if let premiumVoice = englishVoices.first(where: { $0.quality == .premium }) {
            utterance.voice = premiumVoice
            print("🔊 [VOICE SELECTED] ✅ PREMIUM: \(premiumVoice.name) (\(premiumVoice.language))")
        } else if let enhancedVoice = englishVoices.first(where: { $0.quality == .enhanced }) {
            utterance.voice = enhancedVoice
            print("🔊 [VOICE SELECTED] Enhanced: \(enhancedVoice.name) (\(enhancedVoice.language))")
        } else {
            let usVoices = englishVoices.filter { $0.language.hasPrefix("en-US") }
            utterance.voice = usVoices.first
            print("🔊 [VOICE SELECTED] Default: \(usVoices.first?.name ?? "none")")
        }

        // Natural speech parameters optimized for premium voices
        if utterance.voice?.quality == .premium {
            // Premium voices sound best at slightly slower rates with natural pitch
            utterance.rate = 0.52  // Slightly faster than default (0.5) for conversation flow
            utterance.pitchMultiplier = 1.0  // Natural pitch - premium voices already sound good
            utterance.volume = 1.0  // Full volume
        } else {
            // Compact/enhanced voices need more adjustments to sound less robotic
            utterance.rate = 0.58  // Faster = less robotic
            utterance.pitchMultiplier = 1.15  // Higher pitch for friendlier sound
            utterance.volume = 0.9
        }

        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.05

        print("🔊 [VOICE PARAMS] Rate: \(utterance.rate), Pitch: \(utterance.pitchMultiplier), Quality: \(utterance.voice?.quality.rawValue ?? 0)")
        speechSynthesizer.speak(utterance)
    }

    private func trimRoutePolyline(userLocation: CLLocation) {
        guard let fullPolyline = fullRoutePolyline else { return }

        // Throttle trimming: Only update every 2 seconds to prevent performance issues
        let now = Date()
        if let lastTrim = lastTrimTime, now.timeIntervalSince(lastTrim) < 2.0 {
            return  // Skip this update
        }
        lastTrimTime = now

        let points = fullPolyline.points()
        let count = fullPolyline.pointCount

        // OPTIMIZATION: Start searching from last known index instead of 0
        // Users always move forward on route, so closest point only moves forward
        let searchStartIndex = max(0, lastTrimmedIndex - 5)  // Look back 5 points in case of GPS jitter
        let searchEndIndex = min(count, lastTrimmedIndex + 50)  // Only search next 50 points

        var closestIndex = lastTrimmedIndex
        var minDistance = CLLocationDistance.greatestFiniteMagnitude

        // Search only a window around last position instead of entire route
        for i in searchStartIndex..<searchEndIndex {
            let pointCoord = points[i].coordinate
            let pointLocation = CLLocation(latitude: pointCoord.latitude, longitude: pointCoord.longitude)
            let distance = userLocation.distance(from: pointLocation)

            if distance < minDistance {
                minDistance = distance
                closestIndex = i
            }
        }

        lastTrimmedIndex = closestIndex  // Cache for next update

        // Create new polyline from closest point forward
        if closestIndex < count - 1 {
            var remainingCoords: [CLLocationCoordinate2D] = []
            for i in closestIndex..<count {
                remainingCoords.append(points[i].coordinate)
            }

            if !remainingCoords.isEmpty {
                remainingRoutePolyline = MKPolyline(coordinates: remainingCoords, count: remainingCoords.count)
                print("🗺️ [TRIM] Updated remaining route: \(remainingCoords.count) points (from index \(closestIndex)/\(count))")
            }
        }
    }

    // MARK: - Settings Management
    func updateSettings(_ newSettings: NavigationSettings) {
        self.settings = newSettings
        print("⚙️ [SETTINGS] Navigation settings updated")

        // If navigating and highway preference changed, recalculate
        if status == .navigating && settings.avoidHighways != newSettings.avoidHighways {
            print("🔄 [SETTINGS] Highway preference changed during navigation - recalculating")
            if let dest = destination {
                calculateRoutes(to: dest)
            }
        }
    }

    func toggleVoiceGuidance() {
        voiceGuidanceEnabled.toggle()
        settings.voiceGuidanceEnabled = voiceGuidanceEnabled
        settings.save()
        print("🔊 [VOICE] Voice guidance toggled")
    }
}
