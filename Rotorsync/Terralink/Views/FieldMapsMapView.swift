//
//  FieldMapsMapView.swift
//  Rotorsync - Terralink Integration
//
//  Apple Maps integration for displaying field boundaries and flight paths
//

import SwiftUI
import MapKit
import Combine

struct FieldMapsMapView: View {
    let fieldMaps: [FieldMap]
    @Environment(\.dismiss) private var dismiss
    @StateObject private var mapViewModel: TerralinkMapViewModel

    init(fieldMaps: [FieldMap]) {
        self.fieldMaps = fieldMaps
        _mapViewModel = StateObject(wrappedValue: TerralinkMapViewModel(fieldMaps: fieldMaps))
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                // Map View
                MapViewRepresentable(viewModel: mapViewModel)
                    .edgesIgnoringSafeArea(.all)

                // Loading indicator
                if mapViewModel.isLoading {
                    VStack {
                        ProgressView("Loading field geometries...")
                            .padding()
                            .background(Color(.systemBackground).opacity(0.9))
                            .cornerRadius(12)
                    }
                }

                // Field info card (when field is selected)
                if let selectedField = mapViewModel.selectedField {
                    fieldInfoCard(selectedField)
                        .padding()
                        .transition(.move(edge: .bottom))
                }
            }
            .navigationTitle("Field Maps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { mapViewModel.zoomToFitAll() }) {
                            Label("Show All Fields", systemImage: "map")
                        }
                        Button(action: { mapViewModel.toggleMapType() }) {
                            Label(
                                mapViewModel.mapType == .standard ? "Satellite" : "Standard",
                                systemImage: "map.fill"
                            )
                        }
                        Button(action: { mapViewModel.toggleFlightPaths() }) {
                            Label(
                                mapViewModel.showFlightPaths ? "Hide Flight Paths" : "Show Flight Paths",
                                systemImage: "airplane.circle"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear {
            mapViewModel.loadGeometries()
        }
    }

    // MARK: - Field Info Card

    @ViewBuilder
    private func fieldInfoCard(_ fieldMap: FieldMap) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fieldMap.name)
                        .font(.headline)

                    if !fieldMap.notes.isEmpty {
                        Text(fieldMap.notes)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button(action: { mapViewModel.selectedField = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }

            Divider()

            // Field details
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "grid")
                        .foregroundColor(.blue)
                    Text("Area:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.2f acres", fieldMap.area))
                        .fontWeight(.medium)
                }

                if !fieldMap.customer.isEmpty {
                    HStack {
                        Image(systemName: "person")
                            .foregroundColor(.green)
                        Text("Customer:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(fieldMap.customer)
                            .fontWeight(.medium)
                    }
                }

                if !fieldMap.status.isEmpty {
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.orange)
                        Text("Status:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(fieldMap.status.capitalized)
                            .fontWeight(.medium)
                    }
                }

                // Show if flight path is available
                if mapViewModel.hasFlightPath(for: fieldMap) {
                    HStack {
                        Image(systemName: "airplane.circle.fill")
                            .foregroundColor(.purple)
                        Text("Flight Path:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Available")
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                }
            }
            .font(.subheadline)

            // Actions
            HStack(spacing: 12) {
                Button(action: { mapViewModel.zoomToField(fieldMap) }) {
                    HStack {
                        Image(systemName: "scope")
                        Text("Center")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 10)
    }
}

// MARK: - Geometry Data Structure

struct FieldGeometry {
    let fieldMapId: Int
    let requestedCoordinates: [CLLocationCoordinate2D]
    let workedCoordinates: [CLLocationCoordinate2D]?
    let center: CLLocationCoordinate2D
}

// MARK: - Terralink Map View Model

class TerralinkMapViewModel: ObservableObject {
    @Published var fieldMaps: [FieldMap]
    @Published var selectedField: FieldMap?
    @Published var mapType: MKMapType = .standard
    @Published var showFlightPaths: Bool = true
    @Published var isLoading: Bool = false
    @Published var region: MKCoordinateRegion

    var mapView: MKMapView?
    private var geometries: [Int: FieldGeometry] = [:]
    private var cancellables = Set<AnyCancellable>()

    init(fieldMaps: [FieldMap]) {
        self.fieldMaps = fieldMaps

        self.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    }

    func loadGeometries() {
        isLoading = true

        let group = DispatchGroup()

        for fieldMap in fieldMaps {
            group.enter()
            fetchGeometry(for: fieldMap) { geometry in
                if let geometry = geometry {
                    self.geometries[fieldMap.id] = geometry
                    DispatchQueue.main.async {
                        self.addOverlays(for: fieldMap, geometry: geometry)
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.isLoading = false
            self.zoomToFitAll()
        }
    }

    private func fetchGeometry(for fieldMap: FieldMap, completion: @escaping (FieldGeometry?) -> Void) {
        // Use backend API instead of direct Tracmap URLs
        guard let url = URL(string: "https://jobs.rotorsync.com/api/field-maps/\(fieldMap.id)/geometry?type=requested") else {
            completion(nil)
            return
        }

        // Fetch requested geometry through backend
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else {
                print("Failed to fetch geometry for \(fieldMap.name): \(error?.localizedDescription ?? "Unknown error")")
                completion(nil)
                return
            }

            do {
                // Backend wraps GeoJSON in { success, type, data }
                let response = try JSONDecoder().decode(GeometryAPIResponse.self, from: data)
                guard let feature = response.data.features.first else {
                    completion(nil)
                    return
                }

                let requestedCoords = feature.geometry.mapCoordinates
                let center = feature.geometry.centerCoordinate

                // Always try to fetch worked geometry - backend will return it if available
                self.fetchWorkedGeometry(fieldId: fieldMap.id) { workedCoords in
                    let geometry = FieldGeometry(
                        fieldMapId: fieldMap.id,
                        requestedCoordinates: requestedCoords,
                        workedCoordinates: workedCoords,
                        center: center
                    )
                    completion(geometry)
                }
            } catch {
                print("Failed to decode geometry for \(fieldMap.name): \(error)")
                completion(nil)
            }
        }.resume()
    }

    private func fetchWorkedGeometry(fieldId: Int, completion: @escaping ([CLLocationCoordinate2D]?) -> Void) {
        guard let url = URL(string: "https://jobs.rotorsync.com/api/field-maps/\(fieldId)/geometry?type=worked") else {
            print("❌ Invalid URL for worked geometry: \(fieldId)")
            completion(nil)
            return
        }

        print("🔍 Fetching worked geometry for field \(fieldId)...")
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else {
                print("❌ Failed to fetch worked geometry for field \(fieldId): \(error?.localizedDescription ?? "Unknown error")")
                completion(nil)
                return
            }

            do {
                // Backend wraps GeoJSON in { success, type, data }
                let response = try JSONDecoder().decode(GeometryAPIResponse.self, from: data)

                if response.data.features.isEmpty {
                    print("⚠️ No worked geometry features for field \(fieldId)")
                    completion(nil)
                    return
                }

                guard let feature = response.data.features.first else {
                    print("⚠️ No first feature for field \(fieldId)")
                    completion(nil)
                    return
                }

                let coords = feature.geometry.mapCoordinates
                print("✅ Got worked geometry for field \(fieldId): \(coords.count) coordinates")
                completion(coords)
            } catch {
                print("❌ Failed to decode worked geometry for field \(fieldId): \(error)")
                completion(nil)
            }
        }.resume()
    }

    private func addOverlays(for fieldMap: FieldMap, geometry: FieldGeometry) {
        guard let mapView = mapView else {
            print("❌ No mapView available for field \(fieldMap.id)")
            return
        }

        print("🗺️ Adding overlays for field \(fieldMap.id): \(fieldMap.name)")

        // Add requested boundary (outline only)
        let requestedPolygon = MKPolygon(
            coordinates: geometry.requestedCoordinates,
            count: geometry.requestedCoordinates.count
        )
        requestedPolygon.title = "requested_\(fieldMap.id)"
        mapView.addOverlay(requestedPolygon, level: .aboveLabels)
        print("✅ Added requested polygon for field \(fieldMap.id): \(geometry.requestedCoordinates.count) coords")

        // Add worked/flight path (filled)
        if let workedCoords = geometry.workedCoordinates {
            let workedPolygon = MKPolygon(
                coordinates: workedCoords,
                count: workedCoords.count
            )
            workedPolygon.title = "worked_\(fieldMap.id)"
            mapView.addOverlay(workedPolygon, level: .aboveLabels)
            print("✅ Added worked polygon for field \(fieldMap.id): \(workedCoords.count) coords")
        } else {
            print("⚠️ No worked geometry for field \(fieldMap.id)")
        }

        // Add annotation at center
        let annotation = FieldMapAnnotation(fieldMap: fieldMap, coordinate: geometry.center)
        mapView.addAnnotation(annotation)
        print("✅ Added annotation for field \(fieldMap.id)")
    }

    func hasFlightPath(for fieldMap: FieldMap) -> Bool {
        return geometries[fieldMap.id]?.workedCoordinates != nil
    }

    func zoomToFitAll() {
        guard let mapView = mapView, !geometries.isEmpty else { return }

        var minLat: CLLocationDegrees = 90
        var maxLat: CLLocationDegrees = -90
        var minLon: CLLocationDegrees = 180
        var maxLon: CLLocationDegrees = -180

        for geometry in geometries.values {
            for coord in geometry.requestedCoordinates {
                minLat = min(minLat, coord.latitude)
                maxLat = max(maxLat, coord.latitude)
                minLon = min(minLon, coord.longitude)
                maxLon = max(maxLon, coord.longitude)
            }
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.3,
            longitudeDelta: (maxLon - minLon) * 1.3
        )

        let region = MKCoordinateRegion(center: center, span: span)
        mapView.setRegion(region, animated: true)
    }

    func zoomToField(_ fieldMap: FieldMap) {
        guard let mapView = mapView, let geometry = geometries[fieldMap.id] else { return }

        let coords = geometry.requestedCoordinates
        var minLat: CLLocationDegrees = 90
        var maxLat: CLLocationDegrees = -90
        var minLon: CLLocationDegrees = 180
        var maxLon: CLLocationDegrees = -180

        for coord in coords {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.5,
            longitudeDelta: (maxLon - minLon) * 1.5
        )

        let region = MKCoordinateRegion(center: center, span: span)
        mapView.setRegion(region, animated: true)
    }

    func toggleMapType() {
        mapType = mapType == .standard ? .satellite : .standard
        mapView?.mapType = mapType
    }

    func toggleFlightPaths() {
        showFlightPaths.toggle()
        mapView?.overlays.forEach { overlay in
            if let title = (overlay as? MKPolygon)?.title, title.hasPrefix("worked_") {
                mapView?.removeOverlay(overlay)
                if showFlightPaths {
                    mapView?.addOverlay(overlay, level: .aboveLabels)
                }
            }
        }
    }
}

// MARK: - Map View Representable

struct MapViewRepresentable: UIViewRepresentable {
    @ObservedObject var viewModel: TerralinkMapViewModel

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = viewModel.mapType
        mapView.showsUserLocation = true

        viewModel.mapView = mapView

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.mapType = viewModel.mapType
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {
        let viewModel: TerralinkMapViewModel

        init(viewModel: TerralinkMapViewModel) {
            self.viewModel = viewModel
        }

        // Render field boundaries and flight paths
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)

                // Check if it's a requested boundary or worked flight path
                if let title = polygon.title, title.hasPrefix("requested_") {
                    // Requested boundary: outline only, blue
                    renderer.strokeColor = UIColor.systemBlue
                    renderer.fillColor = UIColor.systemBlue.withAlphaComponent(0.1)
                    renderer.lineWidth = 2
                    renderer.lineDashPattern = [5, 5]  // Dashed line for requested
                } else if let title = polygon.title, title.hasPrefix("worked_") {
                    // Worked/flight path: filled, green
                    renderer.fillColor = UIColor.systemGreen.withAlphaComponent(0.3)
                    renderer.strokeColor = UIColor.systemGreen
                    renderer.lineWidth = 3
                }

                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }

        // Customize annotation view
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            if let fieldAnnotation = annotation as? FieldMapAnnotation {
                let identifier = "FieldMapAnnotation"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView

                if annotationView == nil {
                    annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                    annotationView?.canShowCallout = true
                } else {
                    annotationView?.annotation = annotation
                }

                annotationView?.markerTintColor = .systemBlue
                annotationView?.glyphImage = UIImage(systemName: "map.fill")

                return annotationView
            }

            return nil
        }

        // Handle tap on field annotation
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let annotation = view.annotation as? FieldMapAnnotation {
                viewModel.selectedField = annotation.fieldMap
            }
        }
    }
}


struct FieldMapsMapView_Previews: PreviewProvider {
    static var previews: some View {
        FieldMapsMapView(fieldMaps: [])
    }
}
