//
//  FieldMapsMapView.swift
//  Rotorsync - Terralink Integration
//
//  Apple Maps integration for displaying field boundaries
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
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
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
                        Image(systemName: "leaf")
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

                Button(action: {
                    // TODO: Add navigation/directions functionality
                }) {
                    HStack {
                        Image(systemName: "arrow.triangle.turn.up.right.circle")
                        Text("Navigate")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.green)
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

// MARK: - Terralink Map View Model

class TerralinkMapViewModel: ObservableObject {
    @Published var fieldMaps: [FieldMap]
    @Published var selectedField: FieldMap?
    @Published var mapType: MKMapType = .standard
    @Published var region: MKCoordinateRegion

    var mapView: MKMapView?
    init(fieldMaps: [FieldMap]) {
        self.fieldMaps = fieldMaps

        // TODO: Fetch geometry to get field center coordinates
        // For now, use default region
        self.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    }
    func zoomToFitAll() {
        // TODO: Fetch geometry data to calculate bounds
        print("Zoom to fit all - geometry data needed")
    }

    func zoomToField(_ fieldMap: FieldMap) {
        // TODO: Fetch geometry data for this field
        print("Zoom to field: \(fieldMap.name) - geometry data needed")
    }

    func toggleMapType() {
        mapType = mapType == .standard ? .satellite : .standard
        mapView?.mapType = mapType
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

        // Add field overlays
        // TODO: Add field overlays when geometry data is available
        /*
        for fieldMap in viewModel.fieldMaps {
            let overlay = FieldMapOverlay(fieldMap: fieldMap)
            mapView.addOverlay(overlay)
        }
        */
        // Zoom to fit all fields
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            viewModel.zoomToFitAll()
        }

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

        // Render field boundaries
        // TODO: Implement when geometry data is available
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            // TODO: Implement FieldMapOverlay rendering when we have geometry data
            /*
            if let fieldOverlay = overlay as? FieldMapOverlay {
                let renderer = MKPolygonRenderer(
                    polygon: MKPolygon(
                        coordinates: fieldOverlay.coordinates,
                        count: fieldOverlay.coordinates.count
                    )
                )
                renderer.fillColor = UIColor.blue.withAlphaComponent(0.2)
                renderer.strokeColor = UIColor.blue
                renderer.lineWidth = 2
                return renderer
            }
            */
            return MKOverlayRenderer(overlay: overlay)
        }

        // Handle tap on field
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
