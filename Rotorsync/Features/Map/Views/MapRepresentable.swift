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

    let devices: [Device]
    let onPinTapped: (DroppedPinViewModel) -> Void
    let onGroupPinTapped: (APIPin) -> Void
    let onDeviceTapped: (Device) -> Void
    let onFieldTapped: (FieldData) -> Void
    let onLongPressPinDropped: (CLLocationCoordinate2D, String) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mv = MKMapView()
        mv.delegate = context.coordinator
        mv.showsUserLocation = true
        mv.mapType = mapStyle.mapType
        mv.userTrackingMode = userTrackingMode

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
        
        // Update tracking mode
        if uiView.userTrackingMode != userTrackingMode {
            uiView.userTrackingMode = userTrackingMode
        }

        // Update region when there's a new programmatic region to display
        if let region = cameraPosition.region {
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

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapRepresentable
        var isUserInteracting = false  // Add this flag
        private var interactionTimer: Timer?


        init(_ parent: MapRepresentable) {
            self.parent = parent
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
        
        func updateAnnotations(_ mapView: MKMapView, parent: MapRepresentable) {
            // Only update if pins/devices actually changed
            let currentAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
            let expectedCount = parent.droppedPins.count + parent.groupPins.count + parent.devices.count
            
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
            }
            
            // Handle overlays separately
            handleOverlays(mapView, parent: parent)
        }
        
        func handleOverlays(_ mapView: MKMapView, parent: MapRepresentable) {
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
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            // Handle MKPolyline (spray lines)
            if let polyline = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: polyline)

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
            } else if let line = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = .blue
                r.lineWidth = 3
                return r
            }
            return MKOverlayRenderer()
        }

        
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            // User started interacting with map - block programmatic updates
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
            guard !(annotation is MKUserLocation) else { return nil }

            // Handle local dropped pins - RED for personal, BLUE for shared
            if let subtitle = annotation.subtitle as? String, subtitle.starts(with: "dropped_pin_") {
                let id = "droppedPin"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                if view == nil {
                    view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                    view?.canShowCallout = true
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
                return view
            }

            // Handle group pins - BLUE for shared
            if let subtitle = annotation.subtitle as? String, subtitle.starts(with: "group_pin_") {
                let id = "groupPin"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                if view == nil {
                    view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                    view?.canShowCallout = true
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

            // Handle local pins
            if let subtitle = ann.subtitle as? String, subtitle.starts(with: "dropped_pin_") {
                if let title = ann.title as? String,
                   let pin = parent.droppedPins.first(where: { $0.name == title }) {
                    parent.onPinTapped(pin)
                }
            }
            // Handle group pins
            else if let subtitle = ann.subtitle as? String, subtitle.starts(with: "group_pin_") {
                if let title = ann.title as? String,
                   let pin = parent.groupPins.first(where: { $0.name == title }) {
                    parent.onGroupPinTapped(pin)
                }
            }
            // Handle devices
            else if ann.subtitle == "device",
                    let title = ann.title as? String,
                    let dev = parent.devices.first(where: { $0.displayName == title }) {
                parent.onDeviceTapped(dev)
            }
            mapView.deselectAnnotation(ann, animated: true)
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
