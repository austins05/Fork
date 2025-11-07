//
//  FieldMapPreviewView.swift
//  Rotorsync - Preview field map with REAL geometry from Tabula
//

import SwiftUI
import MapKit
import Combine

struct FieldMapPreviewView: View {
    let fieldMap: FieldMap
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel: FieldMapPreviewViewModel

    init(fieldMap: FieldMap) {
        self.fieldMap = fieldMap
        _viewModel = StateObject(wrappedValue: FieldMapPreviewViewModel(fieldMap: fieldMap))
        print("🔷 FieldMapPreviewView.init for: \(fieldMap.name) (ID: \(fieldMap.id))")
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Field info header
                VStack(alignment: .leading, spacing: 12) {
                    Text(fieldMap.name)
                        .font(.title2)
                        .fontWeight(.bold)

                    HStack(spacing: 16) {
                        Label(fieldMap.customer, systemImage: "person.fill")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Label(String(format: "%.1f acres", fieldMap.area), systemImage: "grid")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Label(fieldMap.status.capitalized, systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundColor(statusColor)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))

                Divider()

                // Map preview with real geometry
                ZStack {
                    FieldBoundaryMapView(
                        region: $viewModel.region,
                        boundary: viewModel.coordinates
                    )
                    .edgesIgnoringSafeArea(.bottom)

                    if viewModel.isLoading {
                        ProgressView("Loading field geometry...")
                            .padding()
                            .background(Color(.systemBackground).opacity(0.9))
                            .cornerRadius(10)
                    }

                    if let error = viewModel.errorMessage {
                        VStack {
                            Spacer()
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.9))
                                .cornerRadius(8)
                                .padding(.bottom, 20)
                        }
                    }
                }
            }
            .navigationTitle("Field Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await viewModel.loadGeometry()
                        }
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .task {
                print("🔷 .task modifier fired for preview: \(fieldMap.name) (ID: \(fieldMap.id))")
                await viewModel.loadGeometry()
            }
            .onAppear {
                print("🔷 FieldMapPreviewView.onAppear for: \(fieldMap.name) (ID: \(fieldMap.id))")
            }
            .onDisappear {
                print("🔷 FieldMapPreviewView.onDisappear for: \(fieldMap.name) (ID: \(fieldMap.id))")
            }
        }
    }

    private var statusColor: Color {
        switch fieldMap.status.lowercased() {
        case "complete": return .green
        case "placed": return .blue
        case "in progress": return .orange
        default: return .gray
        }
    }
}

// MARK: - ViewModel

@MainActor
class FieldMapPreviewViewModel: ObservableObject {
    let fieldMap: FieldMap
    @Published var coordinates: [CLLocationCoordinate2D] = []
    @Published var region: MKCoordinateRegion
    @Published var isLoading = false
    @Published var errorMessage: String?

    init(fieldMap: FieldMap) {
        self.fieldMap = fieldMap
        // Default region
        self.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        print("🔷 FieldMapPreviewViewModel.init for: \(fieldMap.name) (ID: \(fieldMap.id))")
    }

    func loadGeometry() async {
        print("🔷 loadGeometry() CALLED for: \(fieldMap.name) (ID: \(fieldMap.id))")
        isLoading = true
        errorMessage = nil

        do {
            print("🔷 Fetching geometry from API for field ID: \(fieldMap.id)")

            // FIXED: Added type: "requested" parameter
            let geometry = try await TabulaAPIService.shared.getFieldGeometry(fieldId: "\(fieldMap.id)", type: "requested")

            print("🔷 Received geometry response for field ID: \(fieldMap.id)")
            print("🔷 Response keys: \(geometry.keys)")

            // Extract coordinates from GeoJSON
            if let coords = extractCoordinates(from: geometry) {
                print("🔷 Extracted \(coords.count) coordinates for: \(fieldMap.name)")
                coordinates = coords

                // Calculate region from coordinates
                if !coords.isEmpty {
                    region = calculateRegion(from: coords)
                    print("🔷 Calculated region for: \(fieldMap.name)")
                }
            } else {
                print("🔷 ❌ No geometry data found for: \(fieldMap.name)")
                errorMessage = "No geometry data found"
            }

        } catch {
            print("🔷 ❌ Geometry load error for \(fieldMap.name): \(error)")
            print("🔷 ❌ Error details: \(error.localizedDescription)")
            errorMessage = "Failed to load geometry: \(error.localizedDescription)"
        }

        isLoading = false
        print("🔷 loadGeometry() COMPLETED for: \(fieldMap.name) (ID: \(fieldMap.id))")
    }

    private func extractCoordinates(from geoJSON: [String: Any]) -> [CLLocationCoordinate2D]? {
        guard let data = geoJSON["data"] as? [String: Any],
              let features = data["features"] as? [[String: Any]],
              let firstFeature = features.first,
              let geometry = firstFeature["geometry"] as? [String: Any],
              let type = geometry["type"] as? String,
              let coordinates = geometry["coordinates"] as? [[[Double]]] else {
            print("🔷 ❌ Failed to extract coordinates from GeoJSON structure")
            return nil
        }

        // Handle Polygon type (first array of coordinates)
        guard type == "Polygon", let ring = coordinates.first else {
            print("🔷 ❌ Not a Polygon type or empty coordinates")
            return nil
        }

        // Convert [[lon, lat]] to CLLocationCoordinate2D
        return ring.compactMap { coord in
            guard coord.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: coord[1], longitude: coord[0])
        }
    }

    private func calculateRegion(from coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else {
            return region
        }

        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude

        for coord in coordinates {
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
            latitudeDelta: (maxLat - minLat) * 1.5, // Add 50% padding
            longitudeDelta: (maxLon - minLon) * 1.5
        )

        return MKCoordinateRegion(center: center, span: span)
    }
}

// MARK: - Map View with Polygon Overlay

struct FieldBoundaryMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let boundary: [CLLocationCoordinate2D]

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.setRegion(region, animated: true)

        // Remove existing overlays
        mapView.removeOverlays(mapView.overlays)

        // Add polygon if we have coordinates
        if boundary.count >= 3 {
            let polygon = MKPolygon(coordinates: boundary, count: boundary.count)
            mapView.addOverlay(polygon)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor = UIColor.blue.withAlphaComponent(0.3)
                renderer.strokeColor = UIColor.blue
                renderer.lineWidth = 2
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
