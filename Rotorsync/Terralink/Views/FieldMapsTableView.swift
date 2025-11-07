//
//  FieldMapsTableView.swift
//  Rotorsync - Full-screen table view for Tabula field maps
//

import SwiftUI
import Combine

struct FieldMapsTableView: View {
    @StateObject private var viewModel = FieldMapsTableViewModel()
    @Environment(\.dismiss) var dismiss
    
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
            .navigationTitle("Field Maps Table")
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
    }
    
    private var tableView: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                // Header Row
                HStack(spacing: 0) {
                    TableHeaderCell(title: "Order ID", width: 80)
                    TableHeaderCell(title: "Customer Name", width: 180)
                    TableHeaderCell(title: "Contractor Name", width: 180)
                    TableHeaderCell(title: "Rts Yes", width: 80)
                    TableHeaderCell(title: "Status", width: 120)
                    TableHeaderCell(title: "Ordered Products", width: 250)
                    TableHeaderCell(title: "Requested Coverage Area (ha)", width: 150)
                    TableHeaderCell(title: "Nominal Area (ha)", width: 130)
                    TableHeaderCell(title: "Real Area (ha)", width: 120)
                    TableHeaderCell(title: "Deleted", width: 80)
                }
                .background(Color(.systemGray5))
                
                Divider()
                
                // Data Rows
                ForEach(viewModel.fieldMaps) { fieldMap in
                    HStack(spacing: 0) {
                        TableCell(text: "\(fieldMap.id)", width: 80)
                        TableCell(text: fieldMap.customer, width: 180)
                        TableCell(text: fieldMap.customer, width: 180) // Contractor same as customer
                        TableCell(text: fieldMap.rts ? "Yes" : "No", width: 80)
                        TableCell(text: fieldMap.status.capitalized, width: 120, color: statusColor(for: fieldMap.status))
                        TableCell(text: fieldMap.productList.isEmpty ? "-" : fieldMap.productList, width: 250)
                        TableCell(text: String(format: "%.2f", fieldMap.area), width: 150, alignment: .trailing)
                        TableCell(text: "0.00", width: 130, alignment: .trailing) // Nominal area placeholder
                        TableCell(text: "0.00", width: 120, alignment: .trailing) // Real area placeholder
                        TableCell(text: fieldMap.deleted ? "Yes" : "No", width: 80)
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
            
            Text("Import field maps to view them in the table")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: { dismiss() }) {
                Text("Go to Field Maps")
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
    @Published var fieldMaps: [FieldMap] = []
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""
    
    private let apiService = TabulaAPIService.shared
    
    func loadInitialData() async {
        // Try loading test data
        await loadTestData()
    }
    
    func loadTestData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Load test customer (ID 5429)
            let maps = try await apiService.getFieldMaps(customerId: "5429")
            fieldMaps = maps.sorted { $0.id > $1.id }
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
