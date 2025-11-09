//
//  FieldMapPreviewSheet.swift
//  Rotorsync - Field Map Preview
//

import SwiftUI
import MapKit
import CoreLocation

struct FieldMapPreviewSheet: View {
    let job: TabulaJob
    @Environment(\.presentationMode) var presentationMode
    @State private var boundaryCoordinates: [[CLLocationCoordinate2D]] = []
    @State private var sprayLines: [[CLLocationCoordinate2D]]? = nil
    @State private var isLoading = true
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    var onImport: () -> Void

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Map Preview
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Map Preview")
                            .font(.headline)

                        if isLoading {
                            ZStack {
                                Rectangle()
                                    .fill(Color(.systemGray6))
                                    .frame(height: 300)
                                    .cornerRadius(12)

                                ProgressView("Loading geometry...")
                            }
                        } else if boundaryCoordinates.isEmpty {
                            ZStack {
                                Rectangle()
                                    .fill(Color(.systemGray6))
                                    .frame(height: 300)
                                    .cornerRadius(12)

                                Text("No geometry available")
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            PreviewMapView(
                                boundaries: boundaryCoordinates,
                                sprayLines: sprayLines,
                                fillColor: job.color ?? "",
                                boundaryColor: job.boundaryColor ?? "",
                                region: $mapRegion
                            )
                            .frame(height: 300)
                            .cornerRadius(12)
                        }
                    }

                    Divider()

                    // Order Details
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Order Details")
                            .font(.headline)

                        DetailRow(label: "Order ID", value: "\(job.id)")
                        DetailRow(label: "Name", value: job.name)
                        DetailRow(label: "Customer", value: job.customer)
                        if let contractor = job.contractor, !contractor.isEmpty {
                            DetailRow(label: "Contractor", value: contractor)
                        }
                        DetailRow(label: "Status", value: job.status.capitalized)
                        DetailRow(label: "RTS", value: job.rts ? "Yes" : "No")
                        DetailRow(label: "Area", value: String(format: "%.2f acres", job.area * 2.47105))

                        if let color = job.color, !color.isEmpty {
                            HStack {
                                Text("Fill Color:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                HStack {
                                    Rectangle()
                                        .fill(Color(hex: colorToHex(color)))
                                        .frame(width: 30, height: 20)
                                        .cornerRadius(4)
                                    Text(color)
                                        .font(.subheadline)
                                }
                            }
                        }

                        if let boundaryColor = job.boundaryColor, !boundaryColor.isEmpty {
                            HStack {
                                Text("Boundary Color:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                HStack {
                                    Rectangle()
                                        .fill(Color(hex: colorToHex(boundaryColor)))
                                        .frame(width: 30, height: 20)
                                        .cornerRadius(4)
                                    Text(boundaryColor)
                                        .font(.subheadline)
                                }
                            }
                        }

                        if !job.address.isEmpty {
                            DetailRow(label: "Address", value: job.address)
                        }

                        if let prodDupli = job.prodDupli, !prodDupli.isEmpty {
                            DetailRow(label: "Product", value: prodDupli)
                        }

                        if !job.productList.isEmpty {
                            DetailRow(label: "Product List", value: job.productList)
                        }

                        if !job.notes.isEmpty {
                            DetailRow(label: "Notes", value: job.notes)
                        }

                        if boundaryCoordinates.count > 1 {
                            DetailRow(label: "Boundaries", value: "\(boundaryCoordinates.count) polygons")
                        }

                        if let sprayCount = sprayLines?.count, sprayCount > 0 {
                            DetailRow(label: "Spray Lines", value: "\(sprayCount) lines")
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    // Import Button
                    Button(action: {
                        onImport()
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        HStack {
                            Image(systemName: "map.fill")
                            Text("Import to Map")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("Preview: \(job.name)")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Close") {
                presentationMode.wrappedValue.dismiss()
            })
        }
        .task {
            await loadGeometry()
        }
    }

    func loadGeometry() async {
        do {
            // Try cache first
            if let cached = FieldGeometryCache.shared.getCachedGeometry(fieldId: job.id) {
                boundaryCoordinates = cached.boundaries
                sprayLines = cached.sprayLines
            } else {
                // Fetch from network
                guard let url = URL(string: "http://192.168.68.226:3000/api/field-maps/\(job.id)/geometry?type=requested") else {
                    isLoading = false
                    return
                }

                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(GeometryAPIResponse.self, from: data)
                boundaryCoordinates = response.data.features.compactMap { $0.geometry.mapCoordinates }

                // Fetch spray lines
                if let sprayURL = URL(string: "http://192.168.68.226:3000/api/field-maps/\(job.id)/geometry?type=worked-detailed") {
                    let (sprayData, _) = try await URLSession.shared.data(from: sprayURL)
                    if let sprayResponse = try? JSONDecoder().decode(GeometryAPIResponse.self, from: sprayData) {
                        sprayLines = sprayResponse.data.features.compactMap { $0.geometry.mapCoordinates }
                    }
                }
            }

            // Calculate map region
            if !boundaryCoordinates.isEmpty {
                let allCoords = boundaryCoordinates.flatMap { $0 }
                if !allCoords.isEmpty {
                    let minLat = allCoords.map { $0.latitude }.min() ?? 0
                    let maxLat = allCoords.map { $0.latitude }.max() ?? 0
                    let minLon = allCoords.map { $0.longitude }.min() ?? 0
                    let maxLon = allCoords.map { $0.longitude }.max() ?? 0

                    let center = CLLocationCoordinate2D(
                        latitude: (minLat + maxLat) / 2,
                        longitude: (minLon + maxLon) / 2
                    )
                    let span = MKCoordinateSpan(
                        latitudeDelta: max(maxLat - minLat, 0.001) * 1.2,
                        longitudeDelta: max(maxLon - minLon, 0.001) * 1.2
                    )
                    mapRegion = MKCoordinateRegion(center: center, span: span)
                }
            }

            isLoading = false
        } catch {
            print("Failed to load preview geometry: \(error)")
            isLoading = false
        }
    }

    func colorToHex(_ colorName: String) -> String {
        let colorMap: [String: String] = [
            "red": "#FF0000", "orange": "#FF8C00", "yellow": "#FFFF00",
            "green": "#00FF00", "teal": "#00FFFF", "blue": "#0000FF",
            "purple": "#9966FF", "pink": "#FF69B4", "magenta": "#FF00FF",
            "gray": "#404040", "grey": "#404040", "black": "#000000", "white": "#FFFFFF"
        ]

        let name = colorName.lowercased().trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("#") {
            return colorName
        }
        return colorMap[name] ?? "#404040"
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.subheadline)
            Spacer()
        }
    }
}

struct PreviewMapView: UIViewRepresentable {
    let boundaries: [[CLLocationCoordinate2D]]
    let sprayLines: [[CLLocationCoordinate2D]]?
    let fillColor: String
    let boundaryColor: String
    @Binding var region: MKCoordinateRegion

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .hybrid
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeOverlays(mapView.overlays)

        // Add boundary polygons
        for (index, boundary) in boundaries.enumerated() {
            let polygon = MKPolygon(coordinates: boundary, count: boundary.count)
            polygon.title = "Boundary \(index + 1)"
            polygon.subtitle = "preview_boundary_\(index)"
            mapView.addOverlay(polygon)
        }

        // Add spray lines
        if let lines = sprayLines {
            for (index, line) in lines.enumerated() {
                var coords = line
                let polyline = MKPolyline(coordinates: &coords, count: coords.count)
                polyline.title = "Spray Line \(index + 1)"
                polyline.subtitle = "preview_spray"
                mapView.addOverlay(polyline)
            }
        }

        mapView.setRegion(region, animated: true)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: PreviewMapView

        init(_ parent: PreviewMapView) {
            self.parent = parent
        }

        func colorToHex(_ colorName: String) -> String {
            let colorMap: [String: String] = [
                "red": "#FF0000", "orange": "#FF8C00", "yellow": "#FFFF00",
                "green": "#00FF00", "teal": "#00FFFF", "blue": "#0000FF",
                "purple": "#9966FF", "pink": "#FF69B4", "magenta": "#FF00FF",
                "gray": "#404040", "grey": "#404040", "black": "#000000", "white": "#FFFFFF"
            ]

            let name = colorName.lowercased().trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("#") {
                return colorName
            }
            return colorMap[name] ?? "#808080"
        }

        func contrastingColor(for hexColor: String) -> UIColor {
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

            let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            return luminance < 0.5 ? UIColor.white : UIColor.black
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)

                // Spray lines
                if polyline.subtitle == "preview_spray" {
                    let fillHex = parent.fillColor.isEmpty ? "#00FF00" : colorToHex(parent.fillColor)
                    let fillCol = Color(hex: fillHex)

                    // Use contrasting color for spray lines
                    renderer.strokeColor = contrastingColor(for: fillHex)
                    renderer.lineWidth = 2
                }

                return renderer
            }

            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)

                // Parse colors
                let fillHex = parent.fillColor.isEmpty ? "#808080" : colorToHex(parent.fillColor)
                let boundaryHex = parent.boundaryColor.isEmpty ? fillHex : colorToHex(parent.boundaryColor)

                let fillCol = Color(hex: fillHex)
                let boundaryCol = Color(hex: boundaryHex)

                renderer.fillColor = UIColor(fillCol).withAlphaComponent(0.4)
                renderer.strokeColor = UIColor(boundaryCol)
                renderer.lineWidth = 2

                return renderer
            }

            return MKOverlayRenderer()
        }
    }
}
