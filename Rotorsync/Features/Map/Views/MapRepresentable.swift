import SwiftUI
import MapKit
import CoreLocation

struct MapRepresentable: UIViewRepresentable {
    @Binding var cameraPosition: MapCameraPosition
    @Binding var droppedPins: [DroppedPinViewModel]
    @Binding var groupPins: [APIPin]
    @Binding var importedFields: [FieldData]
    @Binding var showImportedFields: Bool
    @Binding var hoveredField: FieldData?
    @Binding var path: [CLLocationCoordinate2D]
    @Binding var mapStyle: AppMapStyle
    @Binding var userTrackingMode: MKUserTrackingMode
    @Binding var mapCenter: CLLocationCoordinate2D?
    @Binding var shouldForceUpdate: Bool
    @Binding var isMeasuring: Bool
    @Binding var measurementPins: [(coordinate: CLLocationCoordinate2D, name: String)]
    @Binding var navigationRoute: NavigationRoute?
    @Binding var allRoutes: [NavigationRoute]
    @Binding var selectedRouteIndex: Int?
    @Binding var isNavigating: Bool
    @Binding var waypoints: [CLLocationCoordinate2D]
    @Binding var isAddingWaypoint: Bool
    @Binding var navigationCameraAltitude: CLLocationDistance
    @Binding var flyToLine: [CLLocationCoordinate2D]
    @Binding var remainingRoutePolyline: MKPolyline?
    @Binding var forceOverlayRefresh: Bool
    @Binding var projectionRayLine: [CLLocationCoordinate2D]
    @Binding var projection5MinMark: CLLocationCoordinate2D?
    @Binding var projection10MinMark: CLLocationCoordinate2D?
    @Binding var projection15MinMark: CLLocationCoordinate2D?
    @Binding var flightMode: Bool
    @Binding var headingUpMode: Bool

    let devices: [Device]
    let onPinTapped: (DroppedPinViewModel) -> Void
    let onGroupPinTapped: (APIPin) -> Void
    let onDeviceTapped: (Device) -> Void
    let onFieldTapped: (FieldData) -> Void
    let onLongPressPinDropped: (CLLocationCoordinate2D, String) -> Void
    let onMeasurementTap: (CLLocationCoordinate2D) -> Void
    let onRouteTapped: (Int) -> Void
    let onWaypointTapped: (Int) -> Void
    let onAddWaypoint: (CLLocationCoordinate2D) -> Void
    let onPinDoubleTapped: ((DroppedPinViewModel) -> Void)?
    let onGroupPinDoubleTapped: ((APIPin) -> Void)?

    func makeUIView(context: Context) -> MKMapView {
        let mv = MKMapView()
        mv.delegate = context.coordinator
        mv.showsUserLocation = true
        mv.mapType = mapStyle.mapType
        mv.userTrackingMode = userTrackingMode

        // Enable 3D camera controls
        mv.isPitchEnabled = true
        mv.isRotateEnabled = true
        mv.showsBuildings = true
        print("📷 [3D CAMERA] 3D controls enabled")

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.5
        mv.addGestureRecognizer(longPress)
        
        // Add tap gesture for field selection
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        mv.addGestureRecognizer(tap)

        return mv
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.mapType = mapStyle.mapType
        // IMPORTANT: Update parent reference so coordinator has latest bindings
        context.coordinator.parent = self

        // Don't automatically reset interaction flag during navigation
        // User has full control - they pan freely and manually tap button to re-center
        if !isNavigating {
            // Only manage interaction flag when NOT navigating
            // During navigation, user controls tracking mode with button
        }

        // Update tracking mode
        // IMPORTANT: Don't use followWithHeading during 3D navigation - it forces pitch to 0
        if uiView.userTrackingMode != userTrackingMode {
            // Only set tracking mode if NOT doing 3D navigation
            if !(isNavigating && userTrackingMode == .followWithHeading) {
                uiView.userTrackingMode = userTrackingMode
                print("🗺️ [MAP] Set tracking mode to: \(userTrackingMode.rawValue)")
            } else {
                print("📷 [3D] Skipping tracking mode - using custom 3D camera instead")
            }
        }

        // Custom 3D camera tracking during navigation
        if isNavigating && userTrackingMode == .followWithHeading {
            if let userLocation = uiView.userLocation.location {
                let heading = userLocation.course >= 0 ? userLocation.course : 0
                context.coordinator.update3DNavigationCameraManual(
                    uiView,
                    coordinate: userLocation.coordinate,
                    altitude: navigationCameraAltitude,
                    heading: heading
                )
            }
        }

        // Update helicopter rotation to match heading when flight mode is enabled
        if let annotationView = uiView.view(for: uiView.userLocation) {
            if flightMode, let userLocation = uiView.userLocation.location, userLocation.course >= 0 {
                let heading = userLocation.course
                let radians = CGFloat(heading * .pi / 180.0)
                annotationView.transform = CGAffineTransform(rotationAngle: radians)
                print("🚁 [ROTATION] Helicopter rotated to \(heading)°")
            } else {
                // Reset rotation when flight mode is off
                annotationView.transform = .identity
            }

        // Heading-Up Mode: Rotate map
        if headingUpMode, let userLocation = uiView.userLocation.location, userLocation.course >= 0 {
            let camera = MKMapCamera(lookingAtCenter: userLocation.coordinate, fromEyeCoordinate: userLocation.coordinate, eyeAltitude: uiView.camera.altitude)
            camera.heading = userLocation.course
            uiView.setCamera(camera, animated: true)
        } else if !headingUpMode && uiView.camera.heading != 0 {
            let camera = uiView.camera.copy() as! MKMapCamera
            camera.heading = 0
            uiView.setCamera(camera, animated: true)
        }
        }

        // Update region when there's a new programmatic region to display
        if let region = cameraPosition.region {
            // CRITICAL FIX: Skip manual region updates when MapKit is controlling the camera
            // During .followWithHeading or .follow, MapKit manages zoom/position automatically
            if userTrackingMode == .followWithHeading || userTrackingMode == .follow {
                print("🗺️ [MAP] Skipping region update - tracking mode controls camera (\(userTrackingMode.rawValue))")
                // Let MapKit handle all camera updates during tracking
            } else {
                let cur = uiView.region

                // Check if regions are different
                let centerDiff = abs(cur.center.latitude - region.center.latitude) > 0.0001 ||
                                 abs(cur.center.longitude - region.center.longitude) > 0.0001
                let spanDiff = abs(cur.span.latitudeDelta - region.span.latitudeDelta) > 0.001 ||
                               abs(cur.span.longitudeDelta - region.span.longitudeDelta) > 0.001

                let shouldUpdate = centerDiff || spanDiff

                // Only force update if:
                // 1. Force flag is set (button was just pressed), OR
                // 2. User is not interacting AND there's a significant change
                if shouldUpdate {
                    if shouldForceUpdate {
                        // Force update from button press
                        print("🗺️ FORCING update from button press")

                        // Reset interaction flag to allow this update and future programmatic updates
                        context.coordinator.isUserInteracting = false

                        uiView.setRegion(region, animated: true)

                        // Reset the flag after update
                        DispatchQueue.main.async {
                            self.shouldForceUpdate = false
                        }
                    } else if !context.coordinator.isUserInteracting {
                        // Normal programmatic update (not from button)
                        print("🗺️ Normal programmatic update")
                        uiView.setRegion(region, animated: true)
                    } else {
                        print("⚠️ Skipping update - user is interacting")
                    }
                }
            }
        }
        
        // Update annotations and overlays
        context.coordinator.updateAnnotations(uiView, parent: self)
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    
    // Helper function to create zebra stripe pattern
    private static func createZebraStripePattern() -> UIColor {
        let size = CGSize(width: 20, height: 20)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            // Black background
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            // Yellow diagonal stripes
            UIColor.yellow.setFill()
            let path = UIBezierPath()
            
            // Create diagonal stripes
            for i in stride(from: -20, through: 40, by: 8) {
                path.move(to: CGPoint(x: CGFloat(i), y: 0))
                path.addLine(to: CGPoint(x: CGFloat(i + 4), y: 0))
                path.addLine(to: CGPoint(x: CGFloat(i + 24), y: 20))
                path.addLine(to: CGPoint(x: CGFloat(i + 20), y: 20))
                path.close()
            }
            
            path.fill()
        }
        
        return UIColor(patternImage: image)
    }

    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: MapRepresentable
        var isUserInteracting = false
        var last3DCameraAltitude: CLLocationDistance = 0
        var last3DCameraHeading: CLLocationDirection = 0
        var camera3DApplied: Bool = false
        var lastOverlayUpdateHash: Int = 0


        init(_ parent: MapRepresentable) {
            self.parent = parent
        }


        // MARK: - 3D Camera Management
        func update3DNavigationCameraManual(_ mapView: MKMapView, coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance, heading: CLLocationDirection) {
            // Only update if values changed significantly
            let altitudeChanged = abs(altitude - last3DCameraAltitude) > 100
            let headingChanged = abs(heading - last3DCameraHeading) > 10

            if !camera3DApplied || altitudeChanged || headingChanged {
                print("📷 [3D CAMERA] Updating 3D camera - altitude: \(altitude)m, heading: \(heading)°")

                // Ensure map type supports 3D
                if mapView.mapType == .satellite || mapView.mapType == .hybrid {
                    print("📷 [3D CAMERA] Switching to standard map type")
                    mapView.mapType = .standard
                }

                // Create 3D camera manually (NOT using tracking mode)
                let camera = MKMapCamera(
                    lookingAtCenter: coordinate,
                    fromDistance: altitude,
                    pitch: 50.0,
                    heading: heading
                )

                print("📷 [3D CAMERA] Applying camera - center: \(coordinate.latitude), pitch: 50°")
                mapView.setCamera(camera, animated: camera3DApplied) // Animate after first
                print("📷 [3D CAMERA] Result - pitch: \(mapView.camera.pitch)°")

                last3DCameraAltitude = altitude
                last3DCameraHeading = heading
                camera3DApplied = true
            }
        }

        // MARK: - Flight Mode Projection Helpers

        /// Calculate destination coordinate from start, bearing, and distance
        private func calculateDestination(from start: CLLocationCoordinate2D, bearing: Double, distance: Double) -> CLLocationCoordinate2D {
            let R = 6371000.0 // Earth radius in meters
            let lat1 = start.latitude * .pi / 180.0
            let lon1 = start.longitude * .pi / 180.0
            let brng = bearing * .pi / 180.0

            let lat2 = asin(sin(lat1) * cos(distance / R) + cos(lat1) * sin(distance / R) * cos(brng))
            let lon2 = lon1 + atan2(sin(brng) * sin(distance / R) * cos(lat1),
                                    cos(distance / R) - sin(lat1) * sin(lat2))

            return CLLocationCoordinate2D(
                latitude: lat2 * 180.0 / .pi,
                longitude: lon2 * 180.0 / .pi
            )
        }

        /// Calculate bearing from one coordinate to another
        private func calculateBearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
            let lat1 = start.latitude * .pi / 180.0
            let lon1 = start.longitude * .pi / 180.0
            let lat2 = end.latitude * .pi / 180.0
            let lon2 = end.longitude * .pi / 180.0

            let dLon = lon2 - lon1
            let y = sin(dLon) * cos(lat2)
            let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
            let bearing = atan2(y, x) * 180.0 / .pi

            return (bearing + 360).truncatingRemainder(dividingBy: 360)
        }

        /// Create perpendicular tick mark coordinates at a point
        private func createPerpendicularTick(at point: CLLocationCoordinate2D, bearing: Double) -> [CLLocationCoordinate2D] {
            let perpBearing = (bearing + 90).truncatingRemainder(dividingBy: 360)
            let leftPoint = calculateDestination(from: point, bearing: perpBearing, distance: 75)
            let rightPoint = calculateDestination(from: point, bearing: perpBearing + 180, distance: 75)
            return [leftPoint, rightPoint]
        }

        /// Create arrow polylines at endpoint
        private func createArrowLines(at endpoint: CLLocationCoordinate2D, bearing: Double) -> [[CLLocationCoordinate2D]] {
            let leftArrowPoint = calculateDestination(from: endpoint, bearing: bearing - 135, distance: 100)
            let rightArrowPoint = calculateDestination(from: endpoint, bearing: bearing + 135, distance: 100)

            return [
                [leftArrowPoint, endpoint],
                [endpoint, rightArrowPoint]
            ]
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            let mv = gesture.view as! MKMapView
            let pt = gesture.location(in: mv)
            let coord = mv.convert(pt, toCoordinateFrom: mv)
            
            let pinName = "Pin \(parent.droppedPins.count + 1)"
            parent.onLongPressPinDropped(coord, pinName)
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            let mv = gesture.view as! MKMapView
            let pt = gesture.location(in: mv)
            let coord = mv.convert(pt, toCoordinateFrom: mv)

            // If in measurement mode, drop a measurement pin
            if parent.isMeasuring {
                parent.onMeasurementTap(coord)
                return
            }

            // If in waypoint adding mode, add waypoint at tap location
            if parent.isAddingWaypoint {
                print("📍 [TAP] Adding waypoint at: \(coord.latitude), \(coord.longitude)")
                parent.onAddWaypoint(coord)
                return
            }

            // Check if tap is on a route during route selection
            if !parent.allRoutes.isEmpty {
                for overlay in mv.overlays {
                    if let polyline = overlay as? MKPolyline,
                       polyline.title == "route_option",
                       let subtitle = polyline.subtitle,
                       subtitle.starts(with: "route_") {

                        let routeIndexStr = subtitle.replacingOccurrences(of: "route_", with: "")
                        if let routeIndex = Int(routeIndexStr) {
                            // Check if tap is near this route
                            if isTapNearPolyline(tapPoint: pt, polyline: polyline, mapView: mv) {
                                print("🗺️ [TAP] Selected route \(routeIndex)")
                                parent.onRouteTapped(routeIndex)
                                return
                            }
                        }
                    }
                }
            }

            // Check if tap is inside any field polygon
            for field in parent.importedFields {
                let polygon = MKPolygon(coordinates: field.coordinates, count: field.coordinates.count)
                let renderer = MKPolygonRenderer(polygon: polygon)
                let mapPoint = MKMapPoint(coord)
                let rendererPoint = renderer.point(for: mapPoint)

                if renderer.path.contains(rendererPoint) {
                    parent.onFieldTapped(field)
                    return
                }
            }
        }

        @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended,
                  let annotationView = gesture.view as? MKAnnotationView,
                  let annotation = annotationView.annotation,
                  let subtitle = annotation.subtitle as? String else {
                print("⚠️ [SINGLE-TAP] Could not get annotation from gesture")
                return
            }

            print("📍 [SINGLE-TAP] Single tap on annotation: \(subtitle)")

            // Handle dropped pins - show action sheet
            if subtitle.starts(with: "dropped_pin_") {
                let idString = subtitle.replacingOccurrences(of: "dropped_pin_", with: "")
                if let uuid = UUID(uuidString: idString),
                   let pin = parent.droppedPins.first(where: { $0.id == uuid }) {
                    print("📍 [SINGLE-TAP] Dropped pin - showing action sheet")
                    parent.onPinTapped(pin)
                    return
                }
            }

            // Handle group pins - show action sheet
            if subtitle.starts(with: "group_pin_") {
                let idString = subtitle.replacingOccurrences(of: "group_pin_", with: "")
                if let pin = parent.groupPins.first(where: { $0.id == idString }) {
                    print("📍 [SINGLE-TAP] Group pin - showing action sheet")
                    parent.onGroupPinTapped(pin)
                    return
                }
            }

            print("⚠️ [SINGLE-TAP] Pin not recognized: \(subtitle)")
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended,
                  let annotationView = gesture.view as? MKAnnotationView,
                  let annotation = annotationView.annotation,
                  let subtitle = annotation.subtitle as? String else {
                print("⚠️ [DOUBLE-TAP] Could not get annotation from gesture")
                return
            }

            print("👆👆 [DOUBLE-TAP] Double tap on annotation: \(subtitle)")

            // Handle dropped pins
            if subtitle.starts(with: "dropped_pin_") {
                let idString = subtitle.replacingOccurrences(of: "dropped_pin_", with: "")
                if let uuid = UUID(uuidString: idString),
                   let pin = parent.droppedPins.first(where: { $0.id == uuid }) {
                    print("📍 [DOUBLE-TAP] Dropped pin found, triggering navigation")
                    parent.onPinDoubleTapped?(pin)
                    return
                }
            }

            // Handle group pins
            if subtitle.starts(with: "group_pin_") {
                let idString = subtitle.replacingOccurrences(of: "group_pin_", with: "")
                if let pin = parent.groupPins.first(where: { $0.id == idString }) {
                    print("📍 [DOUBLE-TAP] Group pin found, triggering navigation")
                    parent.onGroupPinDoubleTapped?(pin)
                    return
                }
            }

            print("⚠️ [DOUBLE-TAP] Annotation not recognized as pin: \(subtitle)")
        }


        // Helper to detect if tap is near a polyline
        private func isTapNearPolyline(tapPoint: CGPoint, polyline: MKPolyline, mapView: MKMapView) -> Bool {
            let tapCoord = mapView.convert(tapPoint, toCoordinateFrom: mapView)
            let tapLocation = CLLocation(latitude: tapCoord.latitude, longitude: tapCoord.longitude)

            // Check distance to each point along the polyline
            let points = polyline.points()
            let count = polyline.pointCount

            var minDistance: CLLocationDistance = .greatestFiniteMagnitude

            for i in 0..<count {
                let pointCoord = points[i].coordinate
                let pointLocation = CLLocation(latitude: pointCoord.latitude, longitude: pointCoord.longitude)
                let distance = tapLocation.distance(from: pointLocation)

                if distance < minDistance {
                    minDistance = distance
                }
            }

            // Consider tap "near" if within 100 meters of any route point
            return minDistance < 100
        }
        
        func updateAnnotations(_ mapView: MKMapView, parent: MapRepresentable) {
            // Only update if pins/devices actually changed
            let currentAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
            let projectionMarkersCount = [parent.projection5MinMark, parent.projection10MinMark, parent.projection15MinMark].compactMap { $0 }.count
            let expectedCount = parent.droppedPins.count + parent.groupPins.count + parent.devices.count + parent.measurementPins.count + parent.waypoints.count + projectionMarkersCount

            // Only refresh annotations if count changed
            if currentAnnotations.count != expectedCount {
                mapView.removeAnnotations(currentAnnotations)
                
                // Add local pins
                for pin in parent.droppedPins {
                    let a = MKPointAnnotation()
                    a.coordinate = pin.coordinate
                    a.title = pin.name
                    a.subtitle = "dropped_pin_\(pin.id.uuidString)"
                    mapView.addAnnotation(a)
                }
                
                // Add group pins
                for pin in parent.groupPins {
                    let a = MKPointAnnotation()
                    a.coordinate = CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
                    a.title = pin.name
                    a.subtitle = "group_pin_\(pin.id)"
                    mapView.addAnnotation(a)
                }
                
                // Add devices
                for device in parent.devices {
                    guard let lat = device.latitude, let lon = device.longitude else { continue }
                    let a = MKPointAnnotation()
                    a.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    a.title = device.displayName
                    a.subtitle = "device"
                    mapView.addAnnotation(a)
                }

                // Add measurement pins
                for pin in parent.measurementPins {
                    let a = MKPointAnnotation()
                    a.coordinate = pin.coordinate
                    a.title = pin.name
                    a.subtitle = "measurement_pin"
                    mapView.addAnnotation(a)
                }

                // Add waypoint markers
                for (index, waypoint) in parent.waypoints.enumerated() {
                    let a = MKPointAnnotation()
                    a.coordinate = waypoint
                    a.title = "Waypoint \(index + 1)"
                    a.subtitle = "waypoint_\(index)"
                    mapView.addAnnotation(a)
                }


                // REMOVED: Projection markers now use MKCircle overlays
                /*
                //                 // Add flight mode projection time markers
                                if let mark5 = parent.projection5MinMark {
                                    let a = MKPointAnnotation()
                                    a.coordinate = mark5
                                    a.title = "5 min"
                                    a.subtitle = "projection_5min"
                                    mapView.addAnnotation(a)
                                }
                                if let mark10 = parent.projection10MinMark {
                                    let a = MKPointAnnotation()
                                    a.coordinate = mark10
                                    a.title = "10 min"
                                    a.subtitle = "projection_10min"
                                    mapView.addAnnotation(a)
                                }
                                if let mark15 = parent.projection15MinMark {
                                    let a = MKPointAnnotation()
                                    a.coordinate = mark15
                                    a.title = "15 min"
                                    a.subtitle = "projection_15min"
                                    mapView.addAnnotation(a)
                                }
                */
            }

            // Handle overlays separately
            handleOverlays(mapView, parent: parent)
        }
        
        func handleOverlays(_ mapView: MKMapView, parent: MapRepresentable) {
            // Create hash of current overlay state (broken up for compiler)
            let fieldsHash = parent.importedFields.count * 1000
            let routesHash = parent.allRoutes.count * 100
            let navRouteHash = (parent.navigationRoute != nil ? 50 : 0)
            let measurementHash = parent.measurementPins.count * 10
            let flyLineHash = parent.flyToLine.count * 5
            var projectionHash = 0
            if !parent.projectionRayLine.isEmpty {
                for coord in parent.projectionRayLine {
                    projectionHash += Int(coord.latitude * 1000000) + Int(coord.longitude * 1000000)
                }
            }
            let remainingRouteHash = (parent.remainingRoutePolyline?.pointCount ?? 0)
            let forceRefreshHash = (parent.forceOverlayRefresh ? 1 : 0)
            let overlayHash = fieldsHash + routesHash + navRouteHash + measurementHash + flyLineHash + projectionHash + remainingRouteHash + forceRefreshHash

            // Only update if overlay data actually changed
            if overlayHash == lastOverlayUpdateHash {
                return // Skip - no changes
            }

            print("🗺️ [OVERLAYS] Updating overlays - hash changed from \(lastOverlayUpdateHash) to \(overlayHash)")
            lastOverlayUpdateHash = overlayHash

            mapView.removeOverlays(mapView.overlays)
            
            if parent.showImportedFields {
                for field in parent.importedFields {
                    if field.coordinates.count > 2 {
                        // Add boundary polygon (rendered first, underneath)
                        let poly = MKPolygon(
                            coordinates: field.coordinates + [field.coordinates.first!],
                            count: field.coordinates.count + 1
                        )
                        poly.title = field.name
                        poly.subtitle = "field_\(field.id)"
                        mapView.addOverlay(poly)

                        // Add contractor dash overlay (rendered on top)
                        if let contractorDash = field.contractorDashColor, !contractorDash.isEmpty {
                            let dashPoly = MKPolygon(
                                coordinates: field.coordinates + [field.coordinates.first!],
                                count: field.coordinates.count + 1
                            )
                            dashPoly.title = field.name
                            dashPoly.subtitle = "field_\(field.id)_dash"
                            mapView.addOverlay(dashPoly)
                        }

                        // Add worked geometry (spray lines) as POLYLINES
                        if let workedPolygons = field.workedCoordinates {
                            for (index, workedCoords) in workedPolygons.enumerated() where workedCoords.count > 2 {
                                // Render as a POLYLINE (line path), not a filled polygon
                                var coords = workedCoords
                                let workedLine = MKPolyline(coordinates: &coords, count: coords.count)
                                workedLine.title = field.name + " (Spray Line \(index + 1))"
                                workedLine.subtitle = "spray_line_\(field.id)_\(index)_\(field.color)"
                                mapView.addOverlay(workedLine)
                            }
                        }

                        let sum = field.coordinates.reduce((lat: 0.0, lng: 0.0)) {
                            ($0.lat + $1.latitude, $0.lng + $1.longitude)
                        }
                        let center = CLLocationCoordinate2D(
                            latitude: sum.lat / Double(field.coordinates.count),
                            longitude: sum.lng / Double(field.coordinates.count)
                        )
                        let ann = MKPointAnnotation()
                        ann.coordinate = center
                        ann.title = field.name
                        ann.subtitle = "field_\(field.id)"
                        mapView.addAnnotation(ann)
                    }
                }
            }

            if !parent.path.isEmpty {
                let line = MKPolyline(coordinates: parent.path, count: parent.path.count)
                mapView.addOverlay(line)
            }

            // Add fly-to straight line
            if !parent.flyToLine.isEmpty {
                let line = MKPolyline(coordinates: parent.flyToLine, count: parent.flyToLine.count)
                line.title = "fly_to_line"
                mapView.addOverlay(line)
                print("✈️ [OVERLAY] Added fly-to line with \(parent.flyToLine.count) points")
            }

            // Add flight mode projection ray
            if !parent.projectionRayLine.isEmpty, parent.projectionRayLine.count >= 2 {
                let line = MKPolyline(coordinates: parent.projectionRayLine, count: parent.projectionRayLine.count)
                line.title = "projection_ray_line"
                mapView.addOverlay(line)
                print("🚁 [OVERLAY] Added flight mode projection ray with \(parent.projectionRayLine.count) points")

                // Calculate bearing from the projection line (start to end)
                let start = parent.projectionRayLine[0]
                let end = parent.projectionRayLine[parent.projectionRayLine.count - 1]
                let bearing = calculateBearing(from: start, to: end)

                // Add perpendicular tick marks at 5 and 10 minute marks
                if let mark5 = parent.projection5MinMark {
                    let tickCoords = createPerpendicularTick(at: mark5, bearing: bearing)
                    let tickLine = MKPolyline(coordinates: tickCoords, count: tickCoords.count)
                    tickLine.title = "projection_tick_5min"
                    mapView.addOverlay(tickLine)
                    print("🚁 [OVERLAY] Added 5-min tick mark")
                }
                if let mark10 = parent.projection10MinMark {
                    let tickCoords = createPerpendicularTick(at: mark10, bearing: bearing)
                    let tickLine = MKPolyline(coordinates: tickCoords, count: tickCoords.count)
                    tickLine.title = "projection_tick_10min"
                    mapView.addOverlay(tickLine)
                    print("🚁 [OVERLAY] Added 10-min tick mark")
                }

                // Add arrow at 15 minute mark
                if let mark15 = parent.projection15MinMark {
                    let arrowLines = createArrowLines(at: mark15, bearing: bearing)
                    for (index, arrowCoords) in arrowLines.enumerated() {
                        let arrowLine = MKPolyline(coordinates: arrowCoords, count: arrowCoords.count)
                        arrowLine.title = "projection_arrow_15min_\(index)"
                        mapView.addOverlay(arrowLine)
                    }
                    print("🚁 [OVERLAY] Added 15-min arrow")
                }
            }

            // Add measurement lines between pins
            if parent.measurementPins.count > 1 {
                for i in 0..<(parent.measurementPins.count - 1) {
                    let coords = [parent.measurementPins[i].coordinate, parent.measurementPins[i + 1].coordinate]
                    let line = MKPolyline(coordinates: coords, count: 2)
                    line.title = "measurement_line"
                    line.subtitle = "measurement_segment_\(i)"
                    mapView.addOverlay(line)
                }
            }

            // Add navigation routes
            if !parent.allRoutes.isEmpty {
                // During route selection - show all routes
                for (index, route) in parent.allRoutes.enumerated() {
                    // Use combined polyline for waypoint routes, otherwise use route polyline
                    let basePolyline = route.combinedPolyline ?? route.route.polyline
                    let isSelected = parent.selectedRouteIndex == index

                    print("🗺️ [OVERLAY] Route \(index): hasCombined=\(route.combinedPolyline != nil), points=\(basePolyline.pointCount)")

                    // Create a new polyline with the same coordinates to avoid modifying the original
                    let points = basePolyline.points()
                    var coordinates: [CLLocationCoordinate2D] = []
                    for i in 0..<basePolyline.pointCount {
                        coordinates.append(points[i].coordinate)
                    }

                    // Add white border for selected route (rendered first, underneath)
                    if isSelected {
                        let borderPolyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
                        borderPolyline.title = "route_border"
                        borderPolyline.subtitle = "border_\(index)"
                        mapView.addOverlay(borderPolyline, level: .aboveRoads)
                        print("🗺️ [OVERLAY] Added border for route \(index)")
                    }

                    // Add colored route (rendered on top)
                    let routePolyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
                    routePolyline.title = "route_option"
                    routePolyline.subtitle = "route_\(index)"
                    mapView.addOverlay(routePolyline, level: .aboveRoads)
                    print("🗺️ [OVERLAY] Added route \(index) with \(coordinates.count) points, title=\(routePolyline.title ?? "nil")")
                }
            } else if let navRoute = parent.navigationRoute {
                // During active navigation - show only remaining route (trimmed as user progresses)
                let basePolyline = parent.remainingRoutePolyline ?? navRoute.combinedPolyline ?? navRoute.route.polyline

                print("🗺️ [OVERLAY] Navigation route: remaining=\(parent.remainingRoutePolyline != nil), points=\(basePolyline.pointCount)")

                // Create new polylines with coordinates
                let points = basePolyline.points()
                var coordinates: [CLLocationCoordinate2D] = []
                for i in 0..<basePolyline.pointCount {
                    coordinates.append(points[i].coordinate)
                }

                // Add white border (rendered first)
                let borderPolyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
                borderPolyline.title = "route_border"
                borderPolyline.subtitle = "main_border"
                mapView.addOverlay(borderPolyline, level: .aboveRoads)

                // Add blue route on top
                let routePolyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
                routePolyline.title = "navigation_route"
                routePolyline.subtitle = "main_route"
                mapView.addOverlay(routePolyline, level: .aboveRoads)
                print("🗺️ [OVERLAY] Added navigation route with \(coordinates.count) points (remaining only)")
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            // Handle MKPolyline (spray lines)
            if let polyline = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: polyline)
                print("🎨 [RENDERER] Rendering polyline: title=\(polyline.title ?? "nil"), subtitle=\(polyline.subtitle ?? "nil"), points=\(polyline.pointCount)")

                // Check if it's a white border for selected route
                if polyline.title == "route_border" {
                    print("🎨 [RENDERER] → White border (12px)")
                    r.strokeColor = UIColor.white
                    r.lineWidth = 12 // Wider than the route itself
                    r.lineCap = .round
                    r.lineJoin = .round
                    return r
                }

                // Check if it's a route option during selection
                if polyline.title == "route_option", let subtitle = polyline.subtitle,
                   subtitle.starts(with: "route_") {
                    print("🎨 [RENDERER] → Route option detected")
                    let routeIndexStr = subtitle.replacingOccurrences(of: "route_", with: "")
                    if let routeIndex = Int(routeIndexStr) {
                        let isSelected = parent.selectedRouteIndex == routeIndex

                        // Brighter blue routes for better visibility
                        if isSelected {
                            // Selected route - bright solid blue (border added separately)
                            r.strokeColor = UIColor.systemBlue
                            r.lineWidth = 7
                            print("🎨 [RENDERER] → Selected route \(routeIndex): blue 7px")
                        } else {
                            // Alternate routes - bright blue, slightly transparent
                            r.strokeColor = UIColor.systemBlue.withAlphaComponent(0.75)
                            r.lineWidth = 6
                            print("🎨 [RENDERER] → Alternate route \(routeIndex): blue 75% 6px")
                        }

                        r.lineCap = .round
                        r.lineJoin = .round
                        return r
                    }
                }

                // Check if it's the active navigation route
                if polyline.title == "navigation_route" {
                    r.strokeColor = UIColor.systemBlue
                    r.lineWidth = 7
                    r.lineCap = .round
                    r.lineJoin = .round
                    return r
                }

                // Check if it's a measurement line
                if polyline.title == "measurement_line" {
                    r.strokeColor = UIColor.systemYellow
                    r.lineWidth = 8
                    r.lineDashPattern = [8, 4] // Dashed line
                    return r
                }

                // Check if it's a fly-to straight line
                if polyline.title == "fly_to_line" {
                    r.strokeColor = UIColor.systemGreen
                    r.lineWidth = 5
                    r.lineDashPattern = [10, 5] // Dashed green line
                    r.lineCap = .round
                    return r
                }

                // Check if it's a flight mode projection ray
                if polyline.title == "projection_ray_line" {
                    r.strokeColor = UIColor.systemCyan
                    r.lineWidth = 8
                    r.lineDashPattern = [8, 4] // Dashed cyan line
                    r.lineCap = .round
                    r.alpha = 0.8
                    return r
                }

                // Check if it's a projection tick mark (5 or 10 min)
                if let title = polyline.title, title.starts(with: "projection_tick_") {
                    r.strokeColor = UIColor.systemCyan
                    r.lineWidth = 5
                    r.lineCap = .round
                    r.alpha = 1.0
                    return r
                }

                // Check if it's a projection arrow (15 min)
                if let title = polyline.title, title.starts(with: "projection_arrow_") {
                    r.strokeColor = UIColor.systemCyan
                    r.lineWidth = 2 // 2px width as specified
                    r.lineCap = .round
                    r.alpha = 0.9
                    return r
                }

                // Check if it's a spray line
                if let subtitle = polyline.subtitle, subtitle.starts(with: "spray_line_") {
                    print("✈️ Rendering SPRAY LINE (polyline)")
                    
                    // Extract field color from subtitle (format: spray_line_fieldId_index_hexColor)
                    let parts = subtitle.split(separator: "_")
                    if parts.count >= 4 {
                        let fieldHexColor = String(parts[3])
                        r.strokeColor = Self.contrastingColor(for: fieldHexColor)
                    } else {
                        // Fallback to green if color not found
                        r.strokeColor = UIColor.systemGreen
                    }
                    
                    r.lineWidth = 3
                    return r
                }

                // Default polyline rendering
                r.strokeColor = UIColor.blue
                r.lineWidth = 2
                return r
            }

            // Handle MKPolygon (field boundaries)
            if let poly = overlay as? MKPolygon {
                let r = MKPolygonRenderer(polygon: poly)

                print("🎨 Rendering polygon: \(poly.title ?? "unknown")")
                print("🎨 Polygon subtitle: \(poly.subtitle ?? "none")")

                // Check if it's worked geometry (spray lines) - render as GREEN
                if let subtitle = poly.subtitle, subtitle.starts(with: "worked_") {
                    print("✈️ Rendering SPRAY LINES (worked geometry)")
                    r.fillColor = UIColor.systemGreen.withAlphaComponent(0.4)
                    r.strokeColor = UIColor.systemGreen
                    r.lineWidth = 3
                    return r
                }

                // Check if it's a contractor dash overlay (format: "field_123_dash")
                if let subtitle = poly.subtitle, subtitle.hasSuffix("_dash") {
                    // Extract field ID from "field_123_dash"
                    let parts = subtitle.split(separator: "_")
                    if parts.count >= 2, let fieldId = Int(parts[1]) {
                        if let field = parent.importedFields.first(where: { $0.id == fieldId }) {
                            if let contractorDashHex = field.contractorDashColor, !contractorDashHex.isEmpty {
                                let dashCol = Color(hex: contractorDashHex)
                                r.strokeColor = UIColor(dashCol)
                                r.fillColor = .clear  // No fill - transparent overlay
                                r.lineDashPattern = [3, 16]  // 3pt dash, 16pt gap
                                r.lineWidth = 5
                                print("🔲 Rendering contractor dash overlay: \(contractorDashHex)")
                                return r
                            }
                        }
                    }
                }

                // Extract field ID from subtitle (format: "field_123")
                if let subtitle = poly.subtitle,
                   subtitle.starts(with: "field_"),
                   !subtitle.hasSuffix("_dash"),
                   let fieldIdStr = subtitle.split(separator: "_").last,
                   let fieldId = Int(fieldIdStr) {
                    print("🎨 Looking for field ID: \(fieldId)")

                    // Find field by ID
                    if let field = parent.importedFields.first(where: { $0.id == fieldId }) {
                        print("🎨 Found field: \(field.name), fill: \(field.color), boundary: \(field.boundaryColor ?? "use fill")")
                        // Check for empty color -> use zebra stripes
                        if field.color.isEmpty {
                            print("🎨 🦓 Using ZEBRA STRIPES (no color set)")
                            r.fillColor = MapRepresentable.createZebraStripePattern().withAlphaComponent(0.7)
                            r.strokeColor = UIColor.black
                            r.lineWidth = 3
                            return r
                        }

                        // Fill color
                        let fillCol = Color(hex: field.color)
                        r.fillColor = UIColor(fillCol).withAlphaComponent(0.4)
                        print("🎨 Set fillColor to: \(field.color)")

                        // Stroke color - use boundaryColor if set, otherwise use fill color
                        if let boundaryColorHex = field.boundaryColor, !boundaryColorHex.isEmpty {
                            let strokeCol = Color(hex: boundaryColorHex)
                            r.strokeColor = UIColor(strokeCol)
                            print("🎨 Set strokeColor to boundaryColor: \(boundaryColorHex)")
                        } else {
                            r.strokeColor = UIColor(fillCol)
                            print("🎨 Set strokeColor to fillColor (no boundary): \(field.color)")
                        }

                        r.lineWidth = 3
                        print("🎨 Renderer configured - fillColor: \(r.fillColor?.description ?? "nil"), strokeColor: \(r.strokeColor?.description ?? "nil"), lineWidth: \(r.lineWidth)")
                        return r
                    } else {
                        print("🎨 ❌ Field not found in importedFields")
                        print("🎨 Available field IDs: \(parent.importedFields.map { $0.id })")
                    }
                } else {
                    print("🎨 ❌ Could not parse field ID from subtitle")
                }
                
                // Fallback to red if field not found
                print("🎨 ⚠️ Defaulting to RED")
                r.fillColor = UIColor.red.withAlphaComponent(0.4)
                r.strokeColor = UIColor.red
                r.lineWidth = 3
                return r
            }

            // Fallback for unknown overlay type
            return MKOverlayRenderer()
        }

        
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            // User started interacting with map
            // When user pans during tracking mode, MapKit automatically disables tracking
            isUserInteracting = true
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Update parent's mapCenter every time the map region changes
            DispatchQueue.main.async {
                self.parent.mapCenter = mapView.centerCoordinate
            }

            // Note: We do NOT automatically reset isUserInteracting here
            // This prevents unwanted auto-centering after user moves the map
            // isUserInteracting will only be reset when shouldForceUpdate is triggered

            // Check if zoomed in enough to show field details
            let region = mapView.region
            let zoomLevel = region.span.latitudeDelta

            // Show field card when zoomed in close (smaller span = more zoomed in)
            if zoomLevel < 0.01 {
                let center = mapView.centerCoordinate

                // Find field that contains the center point
                for field in parent.importedFields {
                    let polygon = MKPolygon(coordinates: field.coordinates, count: field.coordinates.count)
                    let renderer = MKPolygonRenderer(polygon: polygon)
                    let mapPoint = MKMapPoint(center)
                    let rendererPoint = renderer.point(for: mapPoint)

                    if renderer.path.contains(rendererPoint) {
                        if parent.hoveredField?.id != field.id {
                            parent.hoveredField = field
                        }
                        return
                    }
                }
            }

            // Not zoomed in enough or no field centered - hide card
            parent.hoveredField = nil
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Customize user location to show helicopter icon only when flight mode is enabled
            if annotation is MKUserLocation {
                // If flight mode is off, return nil to show default blue dot
                guard parent.flightMode else { return nil }

                let id = "userLocation"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                if view == nil {
                    view = MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                } else {
                    view?.annotation = annotation
                }

                // Use R44 helicopter image from assets
                if let helicopterImage = UIImage(named: "r44_helicopter") {
                    // Resize image to appropriate size for map marker
                    let targetSize = CGSize(width: 64, height: 64)
                    let renderer = UIGraphicsImageRenderer(size: targetSize)
                    let resizedImage = renderer.image { _ in
                        helicopterImage.draw(in: CGRect(origin: .zero, size: targetSize))
                    }
                    view?.image = resizedImage
                } else {
                    // Fallback to nil if image not found
                    view?.image = nil
                }

                // Rotation will be handled in updateUIView via transform

                view?.centerOffset = CGPoint(x: 0, y: 0)
                return view
            }

            // Handle flight mode projection time markers - CYAN
            if let subtitle = annotation.subtitle as? String, subtitle.starts(with: "projection_") {
                let id = "projectionMarker"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                if view == nil {
                    view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                    view?.canShowCallout = true
                    view?.displayPriority = .required
                } else {
                    view?.annotation = annotation
                }

                // Set marker appearance based on time mark
                view?.markerTintColor = .systemCyan
                if subtitle.contains("5min") {
                    view?.glyphText = "5"
                } else if subtitle.contains("10min") {
                    view?.glyphText = "10"
                } else if subtitle.contains("15min") {
                    view?.glyphText = "15"
                }

                return view
            }

            // Handle waypoint markers - BLUE numbered circles
            if let subtitle = annotation.subtitle as? String, subtitle.starts(with: "waypoint_") {
                let id = "waypointMarker"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                if view == nil {
                    view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                    view?.canShowCallout = true
                    view?.displayPriority = .required
                } else {
                    view?.annotation = annotation
                }

                // Extract waypoint number
                let waypointIndexStr = subtitle.replacingOccurrences(of: "waypoint_", with: "")
                if let index = Int(waypointIndexStr) {
                    view?.glyphText = "\(index + 1)"
                }

                view?.markerTintColor = .systemBlue
                return view
            }

            // Handle measurement pins - YELLOW
            if let subtitle = annotation.subtitle as? String, subtitle == "measurement_pin" {
                let id = "measurementPin"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                if view == nil {
                    view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                    view?.canShowCallout = true
                    view?.displayPriority = .required
                } else {
                    view?.annotation = annotation
                }
                view?.markerTintColor = .systemYellow
                view?.glyphImage = UIImage(systemName: "ruler")
                return view
            }

            // Handle local dropped pins - RED for personal, BLUE for shared
            if let subtitle = annotation.subtitle as? String, subtitle.starts(with: "dropped_pin_") {
                let id = "droppedPin"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                if view == nil {
                    view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                    view?.canShowCallout = false  // Disabled - using custom gestures
                    view?.displayPriority = .required                } else {
                    view?.annotation = annotation
                    view?.subviews.forEach { subview in
                        if subview.tag == 999 {
                            subview.removeFromSuperview()
                        }
                    }
                }

                let coord = annotation.coordinate
                if let pin = parent.droppedPins.first(where: {
                    abs($0.coordinate.latitude - coord.latitude) < 0.00001 &&
                    abs($0.coordinate.longitude - coord.longitude) < 0.00001
                }) {
                    view?.glyphImage = UIImage(systemName: pin.iconName)
                    
                    if pin.isShared {
                        view?.markerTintColor = .systemBlue  // BLUE for shared
                        addGroupBadge(to: view, color: .systemOrange)  // Orange badge on blue
                    } else {
                        view?.markerTintColor = .systemRed  // RED for personal
                    }
                } else {
                    view?.glyphImage = UIImage(systemName: "mappin")
                    view?.markerTintColor = .systemRed
                }

                // Add gesture recognizers for quick navigation
                if view?.gestureRecognizers?.contains(where: { $0 is UITapGestureRecognizer && ($0 as! UITapGestureRecognizer).numberOfTapsRequired == 2 }) != true {
                    let doubleTap = UITapGestureRecognizer(
                        target: self,
                        action: #selector(Coordinator.handleDoubleTap(_:))
                    )
                    doubleTap.numberOfTapsRequired = 2
                    doubleTap.delegate = self

                    let singleTap = UITapGestureRecognizer(
                        target: self,
                        action: #selector(Coordinator.handleSingleTap(_:))
                    )
                    singleTap.numberOfTapsRequired = 1
                    singleTap.delegate = self

                    // CRITICAL: Single-tap must wait for double-tap to fail
                    singleTap.require(toFail: doubleTap)

                    view?.addGestureRecognizer(doubleTap)
                    view?.addGestureRecognizer(singleTap)
                }

                return view
            }

            // Handle group pins - BLUE for shared
            if let subtitle = annotation.subtitle as? String, subtitle.starts(with: "group_pin_") {
                let id = "groupPin"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                if view == nil {
                    view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                    view?.canShowCallout = false  // Disabled - using custom gestures
                    view?.markerTintColor = .systemBlue  // BLUE for group pins
                } else {
                    view?.annotation = annotation
                    view?.markerTintColor = .systemBlue
                    view?.subviews.forEach { subview in
                        if subview.tag == 999 {
                            subview.removeFromSuperview()
                        }
                    }
                }

                let coord = annotation.coordinate
                if let pin = parent.groupPins.first(where: {
                    abs($0.latitude - coord.latitude) < 0.00001 &&
                    abs($0.longitude - coord.longitude) < 0.00001
                }) {
                    view?.glyphImage = UIImage(systemName: pin.iconName)
                } else {
                    view?.glyphImage = UIImage(systemName: "mappin")
                }
                
                addGroupBadge(to: view, color: .systemOrange)  // Orange badge on blue

                // Add gesture recognizers for quick navigation
                if view?.gestureRecognizers?.contains(where: { $0 is UITapGestureRecognizer && ($0 as! UITapGestureRecognizer).numberOfTapsRequired == 2 }) != true {
                    let doubleTap = UITapGestureRecognizer(
                        target: self,
                        action: #selector(Coordinator.handleDoubleTap(_:))
                    )
                    doubleTap.numberOfTapsRequired = 2
                    doubleTap.delegate = self

                    let singleTap = UITapGestureRecognizer(
                        target: self,
                        action: #selector(Coordinator.handleSingleTap(_:))
                    )
                    singleTap.numberOfTapsRequired = 1
                    singleTap.delegate = self

                    // CRITICAL: Single-tap must wait for double-tap to fail
                    singleTap.require(toFail: doubleTap)

                    view?.addGestureRecognizer(doubleTap)
                    view?.addGestureRecognizer(singleTap)
                }

                return view
            }

            // Handle imported field pins - use field color
            if let subtitle = annotation.subtitle as? String, subtitle.starts(with: "field_"),
               let fieldIdStr = subtitle.split(separator: "_").last,
               let fieldId = Int(fieldIdStr) {
                let id = "fieldPin"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                if view == nil {
                    view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                    view?.canShowCallout = true
                } else {
                    view?.annotation = annotation
                }
                
                // Always show field pins at all zoom levels
                view?.displayPriority = .required
                
                // Find field by ID and use its color
                if let field = parent.importedFields.first(where: { $0.id == fieldId }) {
                    if field.color.isEmpty {
                        // Empty color -> use zebra stripe pattern!
                        view?.markerTintColor = MapRepresentable.createZebraStripePattern()
                        view?.glyphImage = UIImage(systemName: "map.fill")
                    } else {
                        let fieldColor = Color(hex: field.color)
                        view?.markerTintColor = UIColor(fieldColor)
                        view?.glyphImage = UIImage(systemName: "map.fill")
                    }
                } else {
                    // Fallback if field not found
                    view?.markerTintColor = .systemGray
                }
                
                return view
            }

            // Handle devices
            if annotation.subtitle == "device" {
                let id = "device"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                if view == nil {
                    view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                    view?.glyphText = "🚜"
                    view?.markerTintColor = .systemGreen  // Green for devices
                } else { view?.annotation = annotation }
                return view
            }
            return nil
        }
        
        // Helper function to calculate contrasting color
        static func contrastingColor(for hexColor: String) -> UIColor {
            // Handle empty color -> use white for contrast
            if hexColor.isEmpty {
                return UIColor.white
            }
            
            // Parse hex color to RGB
            let hex = hexColor.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            var int: UInt64 = 0
            Scanner(string: hex).scanHexInt64(&int)
            
            let r, g, b: Double
            switch hex.count {
            case 3:
                r = Double((int >> 8) * 17) / 255.0
                g = Double((int >> 4 & 0xF) * 17) / 255.0
                b = Double((int & 0xF) * 17) / 255.0
            case 6:
                r = Double(int >> 16) / 255.0
                g = Double(int >> 8 & 0xFF) / 255.0
                b = Double(int & 0xFF) / 255.0
            default:
                return UIColor.white
            }
            
            // Calculate relative luminance using WCAG formula
            let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            
            // If background is dark (luminance < 0.5), use white lines
            // If background is light (luminance >= 0.5), use black lines
            return luminance < 0.5 ? UIColor.white : UIColor.black
        }
        
        // Helper function to add group badge
        private func addGroupBadge(to view: MKAnnotationView?, color: UIColor) {
            guard let view = view else { return }
            
            let badgeSize: CGFloat = 14
            let badge = UIView(frame: CGRect(x: 24, y: -2, width: badgeSize, height: badgeSize))
            badge.backgroundColor = color  // Use custom color
            badge.layer.cornerRadius = badgeSize / 2
            badge.layer.borderWidth = 1.5
            badge.layer.borderColor = UIColor.white.cgColor
            badge.layer.zPosition = 1000
            badge.tag = 999
            
            badge.layer.shadowColor = UIColor.black.cgColor
            badge.layer.shadowOpacity = 0.3
            badge.layer.shadowOffset = CGSize(width: 0, height: 1)
            badge.layer.shadowRadius = 2
            
            let iconConfig = UIImage.SymbolConfiguration(pointSize: 7, weight: .bold)
            let iconImage = UIImage(systemName: "person.3.fill", withConfiguration: iconConfig)
            let iconView = UIImageView(image: iconImage)
            iconView.tintColor = .white
            iconView.contentMode = .scaleAspectFit
            iconView.frame = CGRect(x: 3, y: 3, width: 8, height: 8)
            badge.addSubview(iconView)
            
            view.addSubview(badge)
            view.bringSubviewToFront(badge)
        }
        
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let ann = view.annotation else { return }


            // Handle waypoint markers (no delay needed - not affected by double-tap)
            if let subtitle = ann.subtitle as? String, subtitle.starts(with: "waypoint_") {
                let waypointIndexStr = subtitle.replacingOccurrences(of: "waypoint_", with: "")
                if let index = Int(waypointIndexStr) {
                    print("📍 [TAP] Waypoint \(index + 1) tapped")
                    parent.onWaypointTapped(index)
                }
                mapView.deselectAnnotation(ann, animated: true)
                return
            }


            mapView.deselectAnnotation(ann, animated: true)
        }

        // MARK: - Tracking Mode Delegate
        func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            print("🗺️ [DELEGATE] Tracking mode changed to: \(mode.rawValue)")

            // Sync with SwiftUI binding
            DispatchQueue.main.async {
                self.parent.userTrackingMode = mode
            }
        }
    }
}

// MARK: - Supporting Types

enum MapCameraPosition {
    case automatic
    case region(MKCoordinateRegion)
    
    var region: MKCoordinateRegion? {
        switch self {
        case .automatic:
            return nil
        case .region(let region):
            return region
        }
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 3: (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default: (r, g, b) = (1, 1, 1)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}
