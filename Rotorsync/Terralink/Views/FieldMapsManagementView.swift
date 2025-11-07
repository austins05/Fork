//
//  FieldMapsManagementView.swift
//  Rotorsync - Terralink Integration
//
//  Main view for managing field maps and customers
//

import SwiftUI
import MapKit

struct FieldMapsManagementView: View {
    @StateObject private var viewModel = FieldMapsViewModel()
    @State private var showingCustomerSearch = false
    @State private var showingMapView = false
    @State private var showingTableView = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Selected customers section
                if !viewModel.selectedCustomers.isEmpty {
                    selectedCustomersSection
                }

                // Imported field maps list
                if viewModel.fieldMaps.isEmpty {
                    emptyStateView
                } else {
                    fieldMapsList
                }
            }
            .navigationTitle("Field Maps")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingCustomerSearch = true }) {
                        Label("Search Customers", systemImage: "magnifyingglass")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.fieldMaps.isEmpty {
                        Button(action: { showingMapView = true }) {
                            Label("View on Map", systemImage: "map")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.fieldMaps.isEmpty {
                        Button(action: { showingTableView = true }) {
                            Label("Table View", systemImage: "tablecells")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCustomerSearch) {
                CustomerSearchView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingMapView) {
                FieldMapsMapView(fieldMaps: viewModel.fieldMaps)
            }
            .sheet(isPresented: $showingTableView) {
                FieldMapsTableView()
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }

    // MARK: - View Components

    private var selectedCustomersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Selected Customers")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.selectedCustomers.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.selectedCustomers) { customer in
                        CustomerChip(customer: customer) {
                            viewModel.removeCustomer(customer)
                        }
                    }
                }
            }

            Button(action: {
                Task {
                    await viewModel.importFieldMaps()
                }
            }) {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                    Text(viewModel.isLoading ? "Importing..." : "Import Field Maps")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.selectedCustomers.isEmpty ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(viewModel.selectedCustomers.isEmpty || viewModel.isLoading)
        }
        .padding()
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "map")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Field Maps")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Search for customers and import their field maps to get started")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: { showingCustomerSearch = true }) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("Search Customers")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fieldMapsList: some View {
        List {
            ForEach(viewModel.fieldMaps) { fieldMap in
                FieldMapRow(fieldMap: fieldMap)
                    .onTapGesture {
                        viewModel.selectedFieldMap = fieldMap
                        showingMapView = true
                    }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }
}

// MARK: - Customer Chip

struct CustomerChip: View {
    let customer: Customer
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(customer.name)
                .font(.subheadline)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.1))
        .foregroundColor(.blue)
        .cornerRadius(16)
    }
}

// MARK: - Field Map Row

// MARK: - Field Map Row

struct FieldMapRow: View {
    let fieldMap: FieldMap

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(fieldMap.name)
                    .font(.headline)

                // Show customer name
                Text(fieldMap.customer)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    // Area
                    Label(String(format: "%.2f acres", fieldMap.area), systemImage: "grid")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Status
                    Label(fieldMap.status.capitalized, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(statusColor)
                        
                    // Order number if available
                    if !fieldMap.orderNumber.isEmpty {
                        Label("#\(fieldMap.orderNumber)", systemImage: "number")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Image(systemName: "map.fill")
                .foregroundColor(.blue)
        }
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        switch fieldMap.status.lowercased() {
        case "complete": return .green
        case "placed": return .blue
        case "in progress", "assigned": return .orange
        default: return .gray
        }
    }

// MARK: - Preview

struct FieldMapsManagementView_Previews: PreviewProvider {
    static var previews: some View {
        FieldMapsManagementView()
    }
}
}
