//
//  JobDetailView.swift
//  Rotorsync - Tabula API Integration
//
//  Detailed view for a single job with map display
//

import SwiftUI
import MapKit

struct JobDetailView: View {
    let job: TabulaJob
    @ObservedObject var viewModel: JobBrowserViewModel
    @State private var showingMap = false
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header card
                headerCard

                // Map preview
                if let geometry = viewModel.jobGeometry,
                   let firstFeature = geometry.features.first {
                    mapPreview(geometry: firstFeature.geometry)
                } else if viewModel.isLoadingGeometry {
                    ProgressView("Loading map...")
                        .frame(height: 200)
                }

                // Job details
                detailsCard

                // Products
                if let detail = viewModel.jobDetail,
                   let productRates = detail.productRates,
                   !productRates.isEmpty {
                    productsCard(productRates: productRates)
                }

                // Actions
                actionsCard
            }
            .padding()
        }
        .navigationTitle(job.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel.selectedJob?.id != job.id {
                await viewModel.selectJob(job)
            }
        }
        .sheet(isPresented: $showingMap) {
            if let geometry = viewModel.jobGeometry {
                JobMapView(job: job, geometry: geometry)
            }
        }
    }

    // MARK: - View Components

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(job.name)
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                StatusBadge(status: job.status)
            }

            if !job.customer.isEmpty {
                Label(job.customer, systemImage: "person.fill")
                    .font(.subheadline)
            }

            if !job.orderNumber.isEmpty {
                Label("Order #\(job.orderNumber)", systemImage: "number")
                    .font(.subheadline)
            }

            Divider()

            HStack {
                VStack(alignment: .leading) {
                    Text("Area")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(job.areaFormatted)
                        .font(.headline)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("Modified")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(job.modifiedDateFormatted)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }

    private func mapPreview(geometry: GeoJSONGeometry) -> some View {
        Button(action: { showingMap = true }) {
            ZStack {
                // Simple map preview
                Map(coordinateRegion: .constant(calculateRegion(geometry: geometry)))
                    .frame(height: 200)
                    .cornerRadius(12)
                    .allowsHitTesting(false)

                // Overlay tap hint
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .padding(8)
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                            .padding()
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)

            if !job.address.isEmpty {
                DetailRow(label: "Address", value: job.address)
            }

            if !job.notes.isEmpty {
                DetailRow(label: "Notes", value: job.notes)
            }

            if let dueDate = job.dueDateFormatted {
                DetailRow(label: "Due Date", value: dueDate)
            }

            if !job.productList.isEmpty {
                DetailRow(label: "Products", value: job.productList)
            }

            if let detail = viewModel.jobDetail {
                if !detail.orderType.isEmpty {
                    DetailRow(label: "Order Type", value: detail.orderType.capitalized)
                }

                if !detail.urgency.isEmpty {
                    DetailRow(label: "Urgency", value: detail.urgency)
                }

                if !detail.color.isEmpty {
                    DetailRow(label: "Color", value: detail.color)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }

    private func productsCard(productRates: [ProductRate]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Products")
                .font(.headline)

            ForEach(productRates.indices, id: \.self) { index in
                let productRate = productRates[index]

                if let product = productRate.product {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        if let applicationRate = productRate.applicationRate {
                            Text("\(String(format: "%.1f", applicationRate.rate)) \(applicationRate.unit)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    if index < productRates.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }

    private var actionsCard: some View {
        VStack(spacing: 12) {
            Button(action: { showingMap = true }) {
                HStack {
                    Image(systemName: "map.fill")
                    Text("View on Map")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(viewModel.jobGeometry == nil)

            Button(action: {
                // Share or export functionality
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray5))
                .foregroundColor(.primary)
                .cornerRadius(10)
            }
        }
    }

    // MARK: - Helper Methods

    private func calculateRegion(geometry: GeoJSONGeometry) -> MKCoordinateRegion {
        let coordinates = geometry.mapCoordinates

        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }

        let minLat = coordinates.map { $0.latitude }.min() ?? 0
        let maxLat = coordinates.map { $0.latitude }.max() ?? 0
        let minLon = coordinates.map { $0.longitude }.min() ?? 0
        let maxLon = coordinates.map { $0.longitude }.max() ?? 0

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.2,
            longitudeDelta: (maxLon - minLon) * 1.2
        )

        return MKCoordinateRegion(center: center, span: span)
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }
}

// MARK: - Job Map View

struct JobMapView: View {
    let job: TabulaJob
    let geometry: GeoJSONFeatureCollection
    @Environment(\.dismiss) var dismiss
    @State private var region: MKCoordinateRegion

    init(job: TabulaJob, geometry: GeoJSONFeatureCollection) {
        self.job = job
        self.geometry = geometry

        // Calculate initial region
        if let firstFeature = geometry.features.first {
            let coordinates = firstFeature.geometry.mapCoordinates

            let minLat = coordinates.map { $0.latitude }.min() ?? 0
            let maxLat = coordinates.map { $0.latitude }.max() ?? 0
            let minLon = coordinates.map { $0.longitude }.min() ?? 0
            let maxLon = coordinates.map { $0.longitude }.max() ?? 0

            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )

            let span = MKCoordinateSpan(
                latitudeDelta: (maxLat - minLat) * 1.3,
                longitudeDelta: (maxLon - minLon) * 1.3
            )

            _region = State(initialValue: MKCoordinateRegion(center: center, span: span))
        } else {
            _region = State(initialValue: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            ))
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Map(coordinateRegion: $region, annotationItems: [job]) { job in
                    MapAnnotation(coordinate: region.center) {
                        VStack {
                            Text(job.name)
                                .font(.caption)
                                .padding(6)
                                .background(Color.white)
                                .cornerRadius(8)
                                .shadow(radius: 4)
                        }
                    }
                }
                .ignoresSafeArea()

                // Overlay polygon (simplified for now)
                if let firstFeature = geometry.features.first {
                    PolygonOverlayView(coordinates: firstFeature.geometry.mapCoordinates)
                }
            }
            .navigationTitle(job.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Polygon Overlay View (Simplified)

struct PolygonOverlayView: View {
    let coordinates: [CLLocationCoordinate2D]

    var body: some View {
        // Note: This is a simplified overlay
        // For production, use MKOverlay with proper rendering
        EmptyView()
    }
}

// MARK: - Preview

struct JobDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleJob = TabulaJob(
            id: 37537,
            name: "Test Field",
            customer: "Headings Helicopters",
            area: 30.6338,
            status: "placed",
            orderNumber: "123456",
            requestedUrl: nil,
            workedUrl: nil,
            modifiedDate: Date().timeIntervalSince1970,
            dueDate: Date().timeIntervalSince1970,
            productList: "HH Roundup PowerMax @ 32oz/ac",
            address: "test",
            notes: "test123",
            deleted: false
        )

        NavigationView {
            JobDetailView(job: sampleJob, viewModel: JobBrowserViewModel())
        }
    }
}
