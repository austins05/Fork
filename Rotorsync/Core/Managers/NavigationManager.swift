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
    // MARK: - Version
    private let VERSION = "v35_NO_UTURN_SENSITIVE"

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
    private let offRouteThreshold: CLLocationDistance = 500 // meters (increased from 50 for less false positives)
    private var consecutiveOffRouteCount = 0
    private var lastRerouteTime: Date?
    private var lastTrimmedIndex = 0  // Cache for route trimming optimization
    private var lastTrimTime: Date?  // Throttle route trimming
    private var lastProgressLogTime: Date?  // Throttle progress logging
    private var lastRemoteProgressLogTime: Date?  // Throttle remote progress logging
    private var selectedVoice: AVSpeechSynthesisVoice?  // Cache selected voice
    private var lastDistanceToDestination: Double?  // Track if user is moving away from destination
    private var lastWrongWayCheckTime: Date?  // Throttle wrong-way detection
    private var isRerouting = false  // Track if currently rerouting to auto-resume
    
    // Smart rerouting
    private var lastDistanceToNextStep: Double = 0
    private var wrongWayDetectionCount = 0
    private var pendingRouteOptions: [NavigationRoute] = []  // Store both U-turn and alternate routes
    private var waitingForUserRouteChoice = false
    private var lastHeading: Double = 0
    
    // Missed turn detection
    private var lastDistanceToNextTurn: Double = 0
    private var distanceIncreasingCount = 0
    private var missedTurnDetected = false
    private var hasApproachedTurn = false  // Track if user has gotten close (<100m) to current turn

    // Voice announcement distances (in meters)
    private let announcementDistances: [Double] = [804.672, 304.8, 30.48] // 2640ft (1/2 mile), 1000ft, 100ft

    // MARK: - Initialization
    init(locationManager: LocationManager) {
        self.locationManager = locationManager
        super.init()
        self.voiceGuidanceEnabled = settings.voiceGuidanceEnabled
        setupLocationTracking()
        log("🚀 [VERSION] NavigationManager \(VERSION) initialized")
    }

    // MARK: - Remote Logging Helper
    private func log(_ message: String) {
        RemoteLogger.shared.log(message)
    }
    

    // MARK: - Route Calculation
    func calculateRoutes(to destination: CLLocationCoordinate2D) {
        log("🚀 [VERSION] Starting navigation with \(VERSION)")
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

            // Auto-resume navigation if rerouting
            if self.isRerouting {
                log("🔄 [REROUTE] Auto-resuming navigation with fastest route")
                // Don't clear isRerouting here - let startNavigation() check it first
                self.startNavigation(with: navRoutes[0])
            } else {
                self.status = .selectingRoute(navRoutes)
                print("✅ [NAV MANAGER] Status set to: selectingRoute with \(navRoutes.count) routes")
            }
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

        // Auto-resume navigation if rerouting
        if isRerouting {
            log("🔄 [REROUTE] Auto-resuming navigation with fastest waypoint route")
            // Don't clear isRerouting here - let startNavigation() check it first
            startNavigation(with: combinedRoutes[0])
        } else {
            status = .selectingRoute(combinedRoutes)
        }
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
        // Get call stack info to understand who called this
        let callStack = Thread.callStackSymbols.prefix(5).joined(separator: "\n    ")
        log("🚨 [NAV START] ============================================")
        log("🚨 [NAV START] startNavigation called!")
        log("🚨 [NAV START] Call stack:\n    \(callStack)")
        log("🚨 [NAV START] Previous status: \(status)")
        if let loc = locationManager.userLocation {
            log("🚨 [NAV START] Current location: \(loc.coordinate.latitude), \(loc.coordinate.longitude)")
        } else {
            log("🚨 [NAV START] Current location: UNAVAILABLE")
        }
        log("🚨 [NAV START] ============================================")

        selectedRoute = route

        // Store full route polyline for trimming as user progresses
        fullRoutePolyline = route.combinedPolyline ?? route.route.polyline
        remainingRoutePolyline = fullRoutePolyline // Start with full route

        // Handle waypoint routes specially - combine all segment steps
        if let segments = route.routeSegments, !segments.isEmpty {
            log("🧭 [NAV START] Using \(segments.count) route segments for waypoint route")
            prepareStepsFromSegments(segments, totalDistance: route.distance, totalTime: route.expectedTravelTime)
        } else {
            log("🧭 [NAV START] Using single route with \(route.route.steps.count) steps")
            prepareSteps(from: route.route)
        }

        log("🧭 [NAV START] Prepared \(routeSteps.count) total steps")

        // Debug: Print all steps
        for (index, step) in routeSteps.enumerated() {
            log("🧭 [STEP \(index)] \(step.instruction) - Distance: \(step.distance)m")
        }

        currentStepIndex = 0
        lastTrimmedIndex = 0  // Reset route trimming cache
        lastTrimTime = nil  // Reset throttle
        updateCurrentAndNextSteps()
        status = .navigating
        log("🧭 [NAV START] Status set to: navigating")
        log("🧭 [NAV START] First instruction: \(currentStep?.instruction ?? "none")")

        // Configure audio session for voice guidance
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)
            log("🔊 [AUDIO SESSION] Successfully configured for voice guidance")
        } catch {
            log("⚠️ [AUDIO SESSION] Failed to configure: \(error.localizedDescription)")
        }

        log("🧭 [NAV START] Current step: \(currentStep?.instruction ?? "none")")

        // Announce start or reroute
        if voiceGuidanceEnabled {
            if isRerouting {
                // Reroute announcement - don't say "navigation started" again
                speak("Route recalculated. \(route.distanceString) remaining.")
                log("🔄 [REROUTE ANNOUNCE] Said 'Route recalculated' (not 'Navigation started')")
            } else {
                // Initial navigation start
                speak("Navigation started. \(route.distanceString) to destination.")
                log("🧭 [NAV ANNOUNCE] Said 'Navigation started'")
            }
        }

        // Clear reroute flag AFTER announcement (was being cleared too early)
        isRerouting = false
    }

    // MARK: - Stop Navigation
    func stopNavigation() {
        log("🛑 [NAV STOP] stopNavigation called")
        log("🛑 [NAV STOP] Previous status: \(status)")
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
        isRerouting = false  // Reset reroute flag
        lastProgressLogTime = nil  // Reset progress log throttle
        fullRoutePolyline = nil
        remainingRoutePolyline = nil
        speechSynthesizer.stopSpeaking(at: .immediate)
        log("🛑 [NAV STOP] Navigation stopped, status now: idle")
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
        
        // Track heading for U-turn detection
        if location.course >= 0 {  // Valid heading
            detectAndHandleUTurn(heading: location.course)
        }
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

        // Throttle logging to every 2 seconds to avoid console spam at 10Hz
        let now = Date()
        if lastProgressLogTime == nil || now.timeIntervalSince(lastProgressLogTime!) > 2.0 {
            let stepInstruction = currentStep?.instruction ?? "none"
            let distanceMiles = distanceToNextStep / 1609.34
            print("🔊 [NAV PROGRESS] Step \(currentStepIndex + 1)/\(routeSteps.count): '\(stepInstruction)'")
            print("🔊 [NAV PROGRESS] Distance: \(distanceToNextStep)m (\(Int(distanceToNextStep * 3.28084))ft / \(String(format: "%.2f", distanceMiles))mi)")
            print("🔊 [NAV PROGRESS] Speed: \(location.speed)m/s")
            lastProgressLogTime = now
        }

        // Update remaining route polyline (trim traveled portion)
        trimRoutePolyline(userLocation: location)

        // Check if we should advance to next step (within 20 meters of maneuver point)
        // Conservative threshold to prevent premature advancement
        var justAdvanced = false
        if distanceToNextStep < 20 {
            let nextInstruction = (currentStepIndex + 1 < routeSteps.count) ? routeSteps[currentStepIndex + 1].instruction : "destination"
            log("⏭️  [STEP ADVANCE] Distance < 20m (\(distanceToNextStep)m), advancing from step \(currentStepIndex + 1) to \(currentStepIndex + 2)")
            log("⏭️  [STEP ADVANCE] Leaving: '\(currentStep?.instruction ?? "")' → Going to: '\(nextInstruction)'")
            advanceToNextStep()
            justAdvanced = true
        }

        // Update remaining distance and time
        updateRemainingStats(from: location)

        // Periodic remote progress log (throttled to every 5 seconds)
        if lastRemoteProgressLogTime == nil || now.timeIntervalSince(lastRemoteProgressLogTime!) >= 5.0 {
            let etaDate = Date(timeIntervalSinceNow: remainingTime)
            let etaFormatter = DateFormatter()
            etaFormatter.timeStyle = .short
            let etaString = etaFormatter.string(from: etaDate)
            let remainingMiles = remainingDistance / 1609.34
            let distToTurnFeet = distanceToNextStep * 3.28084
            
            log("📊 [PROGRESS] ETA: \(etaString) | Next turn: \(Int(distanceToNextStep))m (\(Int(distToTurnFeet))ft) | Remaining: \(String(format: "%.1f", remainingMiles))mi")
            lastRemoteProgressLogTime = now
        }


        // Detect missed turns early (before waiting to go 500m off route)
        // Skip if we just advanced - the distance value is stale (from the OLD step)
        if !justAdvanced {
            detectMissedTurn(location: location, distanceToNextStep: distanceToNextStep, nextStepCoordinate: currentStepCoordinate)
        } else {
            log("⏸️  [MISSED TURN SKIP] Skipping detection - just advanced to new step (distance data is stale)")
        }
                // Check if off route
        if isOffRoute(location: location) {
            consecutiveOffRouteCount += 1
            log("⚠️ [OFF ROUTE] Off route detected - count: \(consecutiveOffRouteCount)/5")
            if consecutiveOffRouteCount >= 5 { // 5 consecutive readings to avoid false positives
                log("🔴 [OFF ROUTE] Triggering reroute after 5 consecutive readings")
                handleOffRoute()
            }
        } else {
            if consecutiveOffRouteCount > 0 {
                log("✅ [ON ROUTE] Back on route - resetting counter")
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
                log("🎯 [ARRIVAL CHECK] On final step, distance to destination: \(distanceToDestination)m")
                if distanceToDestination < 30 { // Within 30 meters (~100 ft)
                    log("🎯 [ARRIVED] Within 30m of destination!")
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
            // Removed verbose logging here (called at 10Hz)
            return maneuverCoord
        }

        return destination ?? CLLocationCoordinate2D()
}

    private func advanceToNextStep() {
        log("⏭️  [ADVANCE] Advancing from step \(currentStepIndex) to \(currentStepIndex + 1)")
        currentStepIndex += 1
        updateCurrentAndNextSteps()
        lastAnnouncedDistance = nil // Reset for next step
        
        // Reset missed turn detection when advancing to new step
        lastDistanceToNextTurn = 0
        distanceIncreasingCount = 0
        missedTurnDetected = false
        hasApproachedTurn = false  // Reset - user hasn't approached the new turn yet
        log("⏭️  [ADVANCE] Reset missed turn detection for new step")
        log("⏭️  [ADVANCE] New current step: '\(currentStep?.instruction ?? "none")'")
        
        // NOTE: Don't speak here - announceIfNeeded already spoke at 100ft threshold
        // Speaking here would give us 4 announcements instead of 3
        log("⏭️  [ADVANCE] Step advanced (announcement already given at final threshold)")
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

        // CRITICAL FIX: Use FULL route polyline instead of just current step
        // Current step polyline can be very sparse, causing false off-route detections
        guard let fullPolyline = fullRoutePolyline else {
            // Fallback to current step if no full route available
            let step = routeSteps[currentStepIndex]
            let distance = distanceToPolyline(from: location.coordinate, polyline: step.polyline)
            let isOff = distance > offRouteThreshold
            if isOff {
                log("⚠️ [OFF ROUTE CHECK] Distance from current step: \(Int(distance))m (threshold: \(offRouteThreshold)m)")
            }
            return isOff
        }

        // Check distance to FULL route polyline (more accurate)
        let distance = distanceToPolyline(from: location.coordinate, polyline: fullPolyline)
        let isOff = distance > offRouteThreshold

        // Always log distance for debugging (throttled elsewhere)
        log("📍 [ROUTE CHECK] Distance from route: \(Int(distance))m (threshold: \(offRouteThreshold)m) - \(isOff ? "OFF" : "ON") route")

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
        guard let dest = destination else { return }
        
        log("🔄 [REROUTE] User went off route - calculating smart reroute options")
        
        // Set rerouting flag
        isRerouting = true
        
        // Request BOTH a U-turn route and alternate routes
        calculateSmartReroute(to: dest)
    }
    
    private func calculateSmartReroute(to destination: CLLocationCoordinate2D, avoidUTurn: Bool = false, waypointDistance: Double = 200.0) {
        guard let userLocation = locationManager.userLocation else {
            log("❌ [SMART REROUTE] No user location")
            return
        }

        // If avoiding U-turn, add a waypoint ahead in the user's current direction
        // This forces MapKit to route forward through that point instead of turning around
        if avoidUTurn, let heading = userLocation.course >= 0 ? userLocation.course : nil {
            let waypointCoordinate = calculateCoordinate(from: userLocation.coordinate, distance: waypointDistance, bearing: heading)
            log("🎯 [UTURN AVOID] Adding waypoint \(Int(waypointDistance))m ahead at heading \(Int(heading))°")
            log("🎯 [UTURN AVOID] Route will go: Current Location → Waypoint → Destination")

            // Use segmented routing with the waypoint
            calculateSegmentedRoute(from: userLocation.coordinate, waypoints: [waypointCoordinate], to: destination, retryCount: 0)
            return
        }

        // Standard direct routing (no U-turn avoidance)
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: userLocation.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        request.requestsAlternateRoutes = true  // Get multiple route options

        // Apply highway avoidance if enabled
        if settings.avoidHighways {
            request.highwayPreference = .avoid
        }

        let directions = MKDirections(request: request)
        directions.calculate { [weak self] response, error in
            guard let self = self else { return }

            if let error = error {
                log("❌ [SMART REROUTE] Error: \(error.localizedDescription)")
                self.status = .error(error.localizedDescription)
                self.isRerouting = false
                return
            }

            guard let response = response, !response.routes.isEmpty else {
                log("❌ [SMART REROUTE] No routes found")
                self.status = .error("No route available")
                self.isRerouting = false
                return
            }

            // Convert all routes to NavigationRoute objects
            let navRoutes = response.routes.enumerated().map { index, route in
                NavigationRoute(
                    route: route,
                    name: index == 0 ? "Fastest Route" : "Alternate Route \(index)",
                    distance: route.distance,
                    expectedTravelTime: route.expectedTravelTime,
                    combinedPolyline: nil,
                    routeSegments: nil
                )
            }

            // Check if the route wants us to do a U-turn
            // DISABLED U-turn rejection - waypoint routing fails when waypoint is off-road
            // Instead rely on wrong-way detection to catch issues early
            // Log the route direction for debugging
            if !avoidUTurn, let userHeading = userLocation.course >= 0 ? userLocation.course : nil,
               let firstRoute = response.routes.first,
               !firstRoute.steps.isEmpty {

                // Find the first step with actual polyline data (skip empty steps)
                var routeInitialBearing: Double?
                for step in firstRoute.steps {
                    let pointsPtr = step.polyline.points()
                    let pointCount = step.polyline.pointCount

                    if pointCount >= 2 {
                        // Calculate bearing from first to second point
                        let coord1 = pointsPtr[0].coordinate
                        let coord2 = pointsPtr[1].coordinate
                        routeInitialBearing = coord1.bearing(to: coord2)
                        break
                    }
                }

                if let routeBearing = routeInitialBearing {
                    // Calculate angle difference
                    var angleDiff = abs(userHeading - routeBearing)
                    if angleDiff > 180 {
                        angleDiff = 360 - angleDiff
                    }

                    log("🧭 [ROUTE INFO] User heading: \(Int(userHeading))°, Route direction: \(Int(routeBearing))°, Diff: \(Int(angleDiff))°")
                    if angleDiff > 100 {
                        log("⚠️ [ROUTE INFO] Route requires U-turn (\(Int(angleDiff))° turn)")
                    }
                }
            }

            // Store the route options
            self.pendingRouteOptions = navRoutes

            // Compare routes and announce options
            self.announceRerouteOptions(routes: navRoutes)

            // Start following the fastest route by default
            // User can override by making a U-turn (we'll detect that)
            log("🔄 [SMART REROUTE] Starting with fastest route, watching for U-turn")
            self.startNavigation(with: navRoutes[0])

            // Set flag to watch for user's choice
            self.waitingForUserRouteChoice = true
        }
    }
    
    private func announceRerouteOptions(routes: [NavigationRoute]) {
        guard routes.count >= 1 else { return }
        
        let fastestRoute = routes[0]
        let fastestMiles = fastestRoute.distance / 1609.34
        
        if routes.count > 1 {
            // We have an alternate - announce both options
            let alternateMiles = routes[1].distance / 1609.34
            
            if fastestMiles < alternateMiles {
                // Fastest is likely U-turn
                speak("You missed the turn. You can make a U-turn, adding \(String(format: "%.1f", fastestMiles)) miles, or continue ahead, adding \(String(format: "%.1f", alternateMiles)) miles.")
                log("📢 [REROUTE OPTIONS] U-turn: \(String(format: "%.1f", fastestMiles))mi, Continue: \(String(format: "%.1f", alternateMiles))mi")
            } else {
                // Continue forward is faster
                speak("You missed the turn. Continue ahead for \(String(format: "%.1f", fastestMiles)) miles, or make a U-turn, adding \(String(format: "%.1f", alternateMiles)) miles.")
                log("📢 [REROUTE OPTIONS] Continue: \(String(format: "%.1f", fastestMiles))mi, U-turn: \(String(format: "%.1f", alternateMiles))mi")
            }
        } else {
            // Only one route available
            speak("Rerouting. \(String(format: "%.1f", fastestMiles)) miles to destination.")
            log("📢 [REROUTE OPTIONS] Only one route available: \(String(format: "%.1f", fastestMiles))mi")
        }
    }
    
    private func detectAndHandleUTurn(heading: Double) {
        guard waitingForUserRouteChoice else { return }
        guard pendingRouteOptions.count > 1 else {
            waitingForUserRouteChoice = false
            return
        }
        
        // Calculate heading change
        let headingChange = abs(heading - lastHeading)
        let normalizedChange = min(headingChange, 360 - headingChange)  // Handle 350° -> 10° case
        
        // If user makes a significant heading change (140-220°), they're likely making a U-turn
        if normalizedChange > 140 && normalizedChange < 220 {
            log("🔄 [U-TURN DETECTED] Heading changed by \(Int(normalizedChange))° - switching to U-turn route")
            
            // Switch to the alternate route (assuming it's the U-turn)
            if pendingRouteOptions.count > 1 {
                speak("U-turn detected. Switching to return route.")
                startNavigation(with: pendingRouteOptions[1])
            }
            
            waitingForUserRouteChoice = false
            pendingRouteOptions = []
        }
        
        lastHeading = heading
    }
    
    private func detectMissedTurn(location: CLLocation, distanceToNextStep: Double, nextStepCoordinate: CLLocationCoordinate2D) {
        guard !missedTurnDetected else {
            lastDistanceToNextTurn = distanceToNextStep  // Still update for next time
            return
        }

        // CRITICAL: Check if user is going the WRONG WAY (distance to destination increasing)
        // This bypasses cooldown because it's a critical error
        // ONLY trigger if close to the next turn (<200m) - otherwise they may just be finding a turnaround
        if let destinationCoord = self.destination, distanceToNextStep < 200.0 {
            let currentDistToDestination = location.distance(from: CLLocation(latitude: destinationCoord.latitude, longitude: destinationCoord.longitude))

            if let lastDist = lastDistanceToDestination {
                let distanceIncrease = currentDistToDestination - lastDist

                // Check every 1 second
                let shouldCheck: Bool
                if let lastCheck = lastWrongWayCheckTime {
                    shouldCheck = Date().timeIntervalSince(lastCheck) >= 1.0
                } else {
                    shouldCheck = true
                }

                if shouldCheck {
                    lastWrongWayCheckTime = Date()

                    // Debug: always log the distance change when close to turn
                    log("🔍 [WRONG WAY CHECK] Distance change: \(String(format: "%.2f", distanceIncrease))m (was: \(Int(lastDist))m, now: \(Int(currentDistToDestination))m, speed: \(String(format: "%.1f", location.speed))m/s, distToTurn: \(Int(distanceToNextStep))m)")

                    // If distance increased by more than 1m, user is going wrong way
                    if distanceIncrease > 1.0 && location.speed > 1.0 {  // Moving and going away
                        log("🚨 [WRONG WAY] Distance to destination INCREASING while close to turn! Was: \(Int(lastDist))m, Now: \(Int(currentDistToDestination))m (+\(String(format: "%.2f", distanceIncrease))m)")
                        missedTurnDetected = true
                        handleMissedTurn()
                        lastDistanceToDestination = currentDistToDestination
                        return
                    }
                }
            }

            lastDistanceToDestination = currentDistToDestination
        }

        // Cooldown period after reroute to prevent reroute storms
        // Don't check for missed turns for 10 seconds after a reroute
        if let lastReroute = lastRerouteTime {
            let timeSinceReroute = Date().timeIntervalSince(lastReroute)
            if timeSinceReroute < 10.0 {
                log("⏸️  [MISSED TURN COOLDOWN] Skipping detection - \(String(format: "%.1f", timeSinceReroute))s since last reroute (need 10s)")
                return
            }
        }

        // Track when user gets close to turn
        if distanceToNextStep < 100 {
            hasApproachedTurn = true
        }

        // HEADING-BASED DETECTION (fast and accurate)
        // Check heading if user is far from turn AND distance is increasing
        // OR if distance from ROUTE is high (they may have missed earlier turn)

        let distanceFromRoute = location.distance(from: CLLocation(latitude: nextStepCoordinate.latitude, longitude: nextStepCoordinate.longitude))

        // Check heading if EITHER:
        // A) User approached turn and is now driving away (original logic)
        // B) User is >200m from route AND distance to turn is increasing (missed earlier turn)
        let shouldCheckHeading = (hasApproachedTurn && distanceToNextStep > 100 && lastDistanceToNextTurn > 0 && distanceToNextStep > lastDistanceToNextTurn) ||
                                 (distanceFromRoute > 200 && distanceToNextStep > 100 && lastDistanceToNextTurn > 0 && distanceToNextStep > lastDistanceToNextTurn)

        if shouldCheckHeading {
            let bearingToNextStep = location.coordinate.bearing(to: nextStepCoordinate)
            let userHeading = location.course

            // Only check if we have valid heading data and user is moving
            if userHeading >= 0 && location.speed > 1.0 {  // Valid heading and moving >1 m/s (~2.2 mph)
                // Calculate smallest angle between current heading and desired bearing
                var headingDifference = abs(userHeading - bearingToNextStep)
                if headingDifference > 180 {
                    headingDifference = 360 - headingDifference
                }

                log("🧭 [HEADING CHECK] Should be: \(Int(bearingToNextStep))°, Actually: \(Int(userHeading))°, Diff: \(Int(headingDifference))°, Distance: \(Int(distanceToNextStep))m")

                // If heading is off by more than 90°, user is heading perpendicular or opposite direction
                // This means they definitely missed the turn and are driving away
                if headingDifference > 90 {
                    log("🚨 [MISSED TURN DETECTED - HEADING] Heading off by \(Int(headingDifference))° while >100m from turn - user missed it!")
                    missedTurnDetected = true
                    handleMissedTurn()
                    lastDistanceToNextTurn = distanceToNextStep
                    return
                }
            }
        }

        // DISTANCE-BASED DETECTION (backup for when heading data is unreliable)
        // Only check for missed turns when we're more than 50m away
        if distanceToNextStep > 50 && lastDistanceToNextTurn > 50 {
            if distanceToNextStep > lastDistanceToNextTurn + 20 {  // Distance increased by 20+ meters
                distanceIncreasingCount += 1
                log("⚠️ [MISSED TURN?] Distance to next turn INCREASING: \(Int(lastDistanceToNextTurn))m → \(Int(distanceToNextStep))m (count: \(distanceIncreasingCount)/3)")
                
                if distanceIncreasingCount >= 3 {
                    // User has been driving away from the turn for 3 consecutive checks
                    log("🚨 [MISSED TURN DETECTED - DISTANCE] Distance increased 3 times - user likely missed the turn")
                    missedTurnDetected = true
                    handleMissedTurn()
                }
            } else if distanceToNextStep < lastDistanceToNextTurn - 10 {
                // Distance is decreasing (approaching turn correctly)
                if distanceIncreasingCount > 0 {
                    log("✅ [MISSED TURN] Distance decreasing - resetting counter")
                }
                distanceIncreasingCount = 0
            }
        }

        // Only update lastDistanceToNextTurn when far enough from turn
        // Don't update when close (<100m) to avoid false positives after advancing to new step
        if distanceToNextStep > 100 {
            lastDistanceToNextTurn = distanceToNextStep
        }
    }
    
    /// Calculate a coordinate at a given distance and bearing from a starting point
    /// - Parameters:
    ///   - from: Starting coordinate
    ///   - distance: Distance in meters
    ///   - bearing: Bearing in degrees (0-360), where 0 is north
    /// - Returns: The calculated coordinate
    private func calculateCoordinate(from start: CLLocationCoordinate2D, distance: Double, bearing: Double) -> CLLocationCoordinate2D {
        let earthRadius = 6371000.0  // meters
        let distRatio = distance / earthRadius
        let bearingRad = bearing * .pi / 180

        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180

        let lat2 = asin(sin(lat1) * cos(distRatio) + cos(lat1) * sin(distRatio) * cos(bearingRad))
        let lon2 = lon1 + atan2(sin(bearingRad) * sin(distRatio) * cos(lat1),
                                cos(distRatio) - sin(lat1) * sin(lat2))

        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    private func handleMissedTurn() {
        guard let dest = destination else { return }

        log("🔄 [MISSED TURN] Triggering smart reroute (missed turn detected)")

        // Set rerouting flag
        isRerouting = true

        // Mark reroute time to prevent reroute storms
        lastRerouteTime = Date()

        // Reset missed turn flag
        missedTurnDetected = false
        distanceIncreasingCount = 0

        // Calculate smart reroute options
        calculateSmartReroute(to: dest)
    }


    private func arriveAtDestination() {
        log("🎯 [NAV] Arrived at destination!")
        status = .arrived
        speechSynthesizer.stopSpeaking(at: .immediate)

        if voiceGuidanceEnabled {
            speak("You have arrived at your destination.")
        }
    }

    private func announceIfNeeded(distanceToStep distance: Double) {
        log("🚨 [DEBUG] announceIfNeeded CALLED with distance: \(distance)m")

        // Sanity check: Don't announce if distance is unreasonably far
        if distance > 8046.72 {
            log("🚨 [DEBUG] Distance > 8047m, returning")
            return
        }

        // Initialize lastAnnouncedDistance on first check (don't announce yet)
        if lastAnnouncedDistance == nil {
            // CRITICAL FIX: If starting below first threshold, set to above it
            // This allows announcements to work even when resuming mid-route
            if distance < announcementDistances[0] {
                lastAnnouncedDistance = announcementDistances[0] + 1  // Just above 1/2 mile threshold
                log("📢 [ANNOUNCE] First check - distance \(Int(distance))m is below first threshold. Set baseline to \(Int(lastAnnouncedDistance!))m to enable announcements")
            } else {
                lastAnnouncedDistance = distance
                log("📢 [ANNOUNCE] First check - baseline distance: \(Int(distance))m")
            }
            return
        }

        log("🚨 [DEBUG] Checking thresholds. lastAnnounced: \(lastAnnouncedDistance!)m, current: \(distance)m")

        // Check each threshold for crossing (from far to near)
        // announceDistances = [804.672, 304.8, 30.48] (1/2 mile, 1000ft, 100ft)
        for (index, threshold) in announcementDistances.enumerated() {
            let justCrossed = lastAnnouncedDistance! > threshold && distance <= threshold
            log("🚨 [DEBUG] Threshold[\(index)]=\(threshold)m, justCrossed=\(justCrossed)")

            if justCrossed {
                if let instruction = currentStep?.instruction {
                    let announcement: String
                    switch index {
                    case 0:  // Crossed 804.672m (1/2 mile)
                        announcement = "In half a mile, \(instruction)"
                    case 1:  // Crossed 304.8m (1000 feet)
                        announcement = "In 1000 feet, \(instruction)"
                    default:  // Crossed 30.48m (100 feet) - very close
                        announcement = instruction
                    }

                    log("🔊 [ANNOUNCE] Crossed \(Int(threshold))m threshold: \(announcement)")
                    speak(announcement)
                    lastAnnouncedDistance = distance
                }
                return
            }
        }

        // Update last distance for next comparison
        if distance < lastAnnouncedDistance! {
            log("🚨 [DEBUG] Updating lastAnnouncedDistance from \(lastAnnouncedDistance!) to \(distance)")
            lastAnnouncedDistance = distance
        }
    }
    private func speak(_ text: String) {
        // Log all speech requests
        log("🔊 [VOICE] Speech requested: \"\(text)\"")

        guard voiceGuidanceEnabled else {
            log("🔊 [VOICE] Skipped (voice guidance disabled)")
            return
        }

        // Special tracking for "Navigation started" announcement
        if text.contains("Navigation started") {
            let callStack = Thread.callStackSymbols.prefix(5).joined(separator: "\n    ")
            log("🚨🚨🚨 [VOICE ALERT] ============================================")
            log("🚨🚨🚨 [VOICE ALERT] 'Navigation started' announcement triggered!")
            log("🚨 [VOICE ALERT] Call stack:\n    \(callStack)")
            log("🚨 [VOICE ALERT] Current status: \(status)")
            log("🚨 [VOICE ALERT] Current step: \(currentStepIndex + 1)/\(routeSteps.count)")
            log("🚨 [VOICE ALERT] lastAnnouncedDistance: \(lastAnnouncedDistance?.description ?? "nil")")
            log("🚨🚨🚨 [VOICE ALERT] ============================================")
        }

        speechSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)

        // Select and cache voice (only once per session for performance)
        if selectedVoice == nil {
            let allVoices = AVSpeechSynthesisVoice.speechVoices()
            let englishVoices = allVoices.filter { $0.language.hasPrefix("en") }

            // Select best available: premium > enhanced > default
            if let premiumVoice = englishVoices.first(where: { $0.quality == .premium }) {
                selectedVoice = premiumVoice
                log("🔊 [VOICE] Selected premium: \(premiumVoice.name)")
            } else if let enhancedVoice = englishVoices.first(where: { $0.quality == .enhanced }) {
                selectedVoice = enhancedVoice
                log("🔊 [VOICE] Selected enhanced: \(enhancedVoice.name)")
            } else {
                selectedVoice = englishVoices.first
                log("🔊 [VOICE] Selected default: \(englishVoices.first?.name ?? "system")")
            }
        }

        utterance.voice = selectedVoice

        // Optimize speech parameters based on voice quality
        if selectedVoice?.quality == .premium {
            utterance.rate = 0.52
            utterance.pitchMultiplier = 1.0
            utterance.volume = 1.0
        } else {
            utterance.rate = 0.58
            utterance.pitchMultiplier = 1.15
            utterance.volume = 0.9
        }

        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.05

        log("🔊 [VOICE] Speaking: \"\(text)\"")
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


// MARK: - CLLocationCoordinate2D Extension for Bearing Calculation
extension CLLocationCoordinate2D {
    /// Calculate bearing (direction) from this coordinate to another
    /// Returns: Bearing in degrees (0-360), where 0 is north, 90 is east, etc.
    func bearing(to destination: CLLocationCoordinate2D) -> Double {
        let lat1 = self.latitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let lon1 = self.longitude * .pi / 180
        let lon2 = destination.longitude * .pi / 180

        let dLon = lon2 - lon1

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)

        var bearing = atan2(y, x) * 180 / .pi
        bearing = (bearing + 360).truncatingRemainder(dividingBy: 360)

        return bearing
    }
}
