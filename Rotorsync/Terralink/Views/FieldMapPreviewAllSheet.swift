//
//  FieldMapPreviewAllSheet.swift
//  Rotorsync - Preview All Fields
//

import SwiftUI
import MapKit
import CoreLocation

struct FieldMapPreviewAllSheet: View {
    let jobs: [TabulaJob]
    @Environment(\.presentationMode) var presentationMode
    @State private var fieldsData: [(job: TabulaJob, boundaries: [[CLLocationCoordinate2D]], sprayLines: [[CLLocationCoordinate2D]]?)] = []
    @State private var isLoading = true
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    var onImportAll: () -> Void

    var totalAcres: Double {
        jobs.reduce(0) { $0 + ($1.area * 2.47105) }
    }

    var totalHectares: Double {
        jobs.reduce(0) { $0 + $1.area }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Summary Stats
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Fields")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(jobs.count)")
                            .font(.title2)
                            .bold()
                    }

                    Divider()
                        .frame(height: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Acres")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.2f", totalAcres))
                            .font(.title2)
                            .bold()
                    }

                    Spacer()
                }
                .padding()
                .background(Color(.systemGray6))

                Divider()

                // Map Preview
                if isLoading {
                    ZStack {
                        Color(.systemGray6)
                        ProgressView("Loading \(jobs.count) fields...")
                    }
                } else {
                    PreviewAllMapView(
                        fieldsData: fieldsData,
                        region: $mapRegion
                    )
                }

                Divider()

                // Fields List
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Fields (\(jobs.count))")
                            .font(.headline)
                            .padding(.horizontal)
                            .padding(.top, 12)

                        ForEach(jobs) { job in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(job.name)
                                        .font(.subheadline)
                                        .bold()
                                    Text("Order #\(job.id) - \(job.customer)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if let color = job.color, !color.isEmpty {
                                    Rectangle()
                                        .fill(Color(hex: colorToHex(color)))
                                        .frame(width: 24, height: 24)
                                        .cornerRadius(4)
                                }

                                Text(String(format: "%.2f ac", job.area * 2.47105))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
                .frame(maxHeight: 200)

                // Import All Button
                Button(action: {
                    onImportAll()
                    presentationMode.wrappedValue.dismiss()
                }) {
                    HStack {
                        Image(systemName: "map.fill")
                        Text("Import All \(jobs.count) Fields to Map")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Preview \(jobs.count) Fields")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Close") {
                presentationMode.wrappedValue.dismiss()
            })
        }
        .task {
            await loadAllGeometry()
        }
    }

    func loadAllGeometry() async {
        var loadedFields: [(job: TabulaJob, boundaries: [[CLLocationCoordinate2D]], sprayLines: [[CLLocationCoordinate2D]]?)] = []

        for job in jobs {
            // Try cache first
            if let cached = FieldGeometryCache.shared.getCachedGeometry(fieldId: job.id) {
                loadedFields.append((job, cached.boundaries, cached.sprayLines))
            } else {
                // Fetch from network
                do {
                    guard let url = URL(string: "http://192.168.68.226:3000/api/field-maps/\(job.id)/geometry?type=requested") else {
                        continue
                    }

                    let (data, _) = try await URLSession.shared.data(from: url)
                    let response = try JSONDecoder().decode(GeometryAPIResponse.self, from: data)
                    let boundaries = response.data.features.compactMap { $0.geometry.mapCoordinates }

                    // Fetch spray lines
                    var sprayLines: [[CLLocationCoordinate2D]]? = nil
                    if let sprayURL = URL(string: "http://192.168.68.226:3000/api/field-maps/\(job.id)/geometry?type=worked-detailed") {
                        if let (sprayData, _) = try? await URLSession.shared.data(from: sprayURL),
                           let sprayResponse = try? JSONDecoder().decode(GeometryAPIResponse.self, from: sprayData) {
                            sprayLines = sprayResponse.data.features.compactMap { $0.geometry.mapCoordinates }
                        }
                    }

                    loadedFields.append((job, boundaries, sprayLines))
                } catch {
                    print("Failed to load geometry for job \(job.id): \(error)")
                }
            }
        }

        fieldsData = loadedFields

        // Calculate map region to fit all fields
        var allCoords: [CLLocationCoordinate2D] = []
        for field in fieldsData {
            allCoords.append(contentsOf: field.boundaries.flatMap { $0 })
        }

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
                latitudeDelta: max(maxLat - minLat, 0.001) * 1.3,
                longitudeDelta: max(maxLon - minLon, 0.001) * 1.3
            )
            mapRegion = MKCoordinateRegion(center: center, span: span)
        }

        isLoading = false
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
}

struct PreviewAllMapView: UIViewRepresentable {
    let fieldsData: [(job: TabulaJob, boundaries: [[CLLocationCoordinate2D]], sprayLines: [[CLLocationCoordinate2D]]?)]
    @Binding var region: MKCoordinateRegion

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .hybrid
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeOverlays(mapView.overlays)

        // Add all fields
        for (index, fieldData) in fieldsData.enumerated() {
            let job = fieldData.job
            let boundaries = fieldData.boundaries
            let sprayLines = fieldData.sprayLines

            // Add boundaries
            for (boundaryIndex, boundary) in boundaries.enumerated() {
                let polygon = MKPolygon(coordinates: boundary, count: boundary.count)
                polygon.title = job.name
                polygon.subtitle = "preview_all_\(job.id)_\(boundaryIndex)"
                mapView.addOverlay(polygon)
            }

            // Add spray lines
            if let lines = sprayLines {
                for (lineIndex, line) in lines.enumerated() {
                    var coords = line
                    let polyline = MKPolyline(coordinates: &coords, count: coords.count)
                    polyline.title = "\(job.name) Spray"
                    polyline.subtitle = "preview_spray_\(job.id)_\(lineIndex)_\(job.color ?? "")"
                    mapView.addOverlay(polyline)
                }
            }
        }

        mapView.setRegion(region, animated: true)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: PreviewAllMapView

        init(_ parent: PreviewAllMapView) {
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

                // Spray lines - extract color from subtitle
                if let subtitle = polyline.subtitle, subtitle.starts(with: "preview_spray_") {
                    let parts = subtitle.split(separator: "_")
                    if parts.count >= 4 {
                        let fieldColor = String(parts[3])
                        let fillHex = fieldColor.isEmpty ? "#00FF00" : colorToHex(fieldColor)
                        renderer.strokeColor = contrastingColor(for: fillHex)
                        renderer.lineWidth = 2
                    }
                }

                return renderer
            }

            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)

                // Extract job ID from subtitle
                if let subtitle = polygon.subtitle, subtitle.starts(with: "preview_all_") {
                    let parts = subtitle.split(separator: "_")
                    if parts.count >= 3, let jobId = Int(parts[2]) {
                        // Find the job
                        if let fieldData = parent.fieldsData.first(where: { $0.job.id == jobId }) {
                            let job = fieldData.job

                            // Parse colors
                            let fillHex = job.color.flatMap { colorToHex($0) } ?? "#808080"
                            let boundaryHex = job.boundaryColor.flatMap { colorToHex($0) } ?? fillHex

                            let fillCol = Color(hex: fillHex)
                            let boundaryCol = Color(hex: boundaryHex)

                            renderer.fillColor = UIColor(fillCol).withAlphaComponent(0.4)
                            renderer.strokeColor = UIColor(boundaryCol)
                            renderer.lineWidth = 2
                        }
                    }
                }

                return renderer
            }

            return MKOverlayRenderer()
        }
    }
}
