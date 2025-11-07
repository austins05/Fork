//
//  FieldMapsTableView.swift
//  Rotorsync - Full-screen table view for Tabula field maps
//

import SwiftUI
import Combine

struct FieldMapsTableView: View {
    @StateObject private var viewModel = FieldMapsTableViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    ProgressView("Loading jobs...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.fieldMaps.isEmpty {
                    emptyStateView
                } else {
                    tableView
                }
            }
            .navigationTitle("Field Maps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await viewModel.refreshData()
                        }
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .task {
                await viewModel.loadInitialData()
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var tableView: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                // Header Row
                HStack(spacing: 0) {
                    TableHeaderCell(title: "Customer Name", width: 180)
                    TableHeaderCell(title: "Contractor Name", width: 180)
                    TableHeaderCell(title: "Order ID", width: 100)
                    TableHeaderCell(title: "RTS", width: 80)
                    TableHeaderCell(title: "Requested Coverage Area (ha)", width: 180)
                    TableHeaderCell(title: "Status", width: 120)
                    TableHeaderCell(title: "Ordered Products", width: 250)
                    TableHeaderCell(title: "Notes", width: 200)
                    TableHeaderCell(title: "Application Rate", width: 150)
                    TableHeaderCell(title: "Map Address", width: 200)
                }
                .background(Color(.systemGray5))

                Divider()

                // Data Rows
                ForEach(viewModel.fieldMaps) { fieldMap in
                    HStack(spacing: 0) {
                        TableCell(text: fieldMap.customer, width: 180)
                        TableCell(text: fieldMap.customer, width: 180) // Contractor same as customer
                        TableCell(text: "\(fieldMap.id)", width: 100)
                        TableCell(text: fieldMap.rts ? "Yes" : "No", width: 80, color: fieldMap.rts ? .green : .gray)
                        TableCell(text: String(format: "%.2f", fieldMap.area), width: 180, alignment: .trailing)
                        TableCell(text: fieldMap.status.capitalized, width: 120, color: statusColor(for: fieldMap.status))
                        TableCell(text: fieldMap.productList.isEmpty ? "-" : fieldMap.productList, width: 250)
                        TableCell(text: fieldMap.notes.isEmpty ? "-" : fieldMap.notes, width: 200)
                        TableCell(text: "-", width: 150) // Application rate placeholder
                        TableCell(text: fieldMap.address.isEmpty ? "-" : fieldMap.address, width: 200)
                    }
                    .background(Color(.systemBackground))

                    Divider()
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tablecells")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Field Maps")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Field maps will appear here when available")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: {
                Task {
                    await viewModel.refreshData()
                }
            }) {
                Text("Refresh")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusColor(for status: String) -> Color {
        switch status.lowercased() {
        case "complete": return .green
        case "pending": return .blue
        case "placed": return .blue
        case "in progress", "assigned": return .orange
        default: return .primary
        }
    }
}

// MARK: - Table Cell Components

struct TableHeaderCell: View {
    let title: String
    let width: CGFloat

    var body: some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .lineLimit(2)
    }
}

struct TableCell: View {
    let text: String
    let width: CGFloat
    var alignment: Alignment = .leading
    var color: Color = .primary

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(color)
            .frame(width: width, alignment: alignment)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .lineLimit(2)
    }
}

// MARK: - ViewModel

@MainActor
class FieldMapsTableViewModel: ObservableObject {
    @Published var fieldMaps: [TabulaJob] = []
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""

    private let apiService = TabulaAPIService.shared

    func loadInitialData() async {
        await loadTestData()
    }

    func loadTestData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Load test customer (ID 5429)
            let response = try await apiService.session.data(from: URL(string: "http://192.168.68.226:3000/api/field-maps/customer/5429")!)
            let apiResponse = try JSONDecoder().decode(JobsAPIResponse.self, from: response.0)
            fieldMaps = apiResponse.data.sorted { $0.id > $1.id }
        } catch {
            errorMessage = "Failed to load field maps: \(error.localizedDescription)"
            showError = true
        }
    }

    func refreshData() async {
        await loadTestData()
    }
}

// MARK: - Preview

struct FieldMapsTableView_Previews: PreviewProvider {
    static var previews: some View {
        FieldMapsTableView()
    }
}
