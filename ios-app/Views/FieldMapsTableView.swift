//
//  FieldMapsTableView.swift
//  Rotorsync - Full-screen table view for Tabula field maps
//

import SwiftUI
import Combine

struct FieldMapsTableView: View {
    @StateObject private var viewModel = FieldMapsTableViewModel()
    @State private var selectedJobs: Set<Int> = []
    @State private var isSelectionMode = false

    // Filter states
    @State private var customerFilter = ""
    @State private var contractorFilter = ""
    @State private var orderIdFilter = ""
    @State private var rtsFilter = "All"
    @State private var coverageAreaFilter = ""
    @State private var statusFilter = ""
    @State private var productFilter = ""
    @State private var notesFilter = ""
    @State private var applicationRateFilter = ""
    @State private var mapAddressFilter = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Selection toolbar
                if isSelectionMode && !selectedJobs.isEmpty {
                    selectionToolbar
                }

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
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        isSelectionMode.toggle()
                        if !isSelectionMode {
                            selectedJobs.removeAll()
                        }
                    }) {
                        Text(isSelectionMode ? "Done" : "Select")
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
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var selectionToolbar: some View {
        HStack {
            Text("\(selectedJobs.count) selected")
                .font(.headline)

            Spacer()

            Button(action: {
                // Select all
                selectedJobs = Set(viewModel.fieldMaps.map { $0.id })
            }) {
                Text("Select All")
                    .font(.subheadline)
            }

            Button(action: {
                selectedJobs.removeAll()
            }) {
                Text("Clear")
                    .font(.subheadline)
            }
            .padding(.leading, 8)
        }
        .padding()
        .background(Color(.systemGray6))
    }

    func matchesAreaFilter(area: Double, filter: String) -> Bool {
        let trimmed = filter.trimmingCharacters(in: .whitespaces)

        // Handle range format: "2-3" or "2 - 3"
        if trimmed.contains("-") {
            let parts = trimmed.components(separatedBy: "-").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2,
               let min = Double(parts[0]),
               let max = Double(parts[1]) {
                return area >= min && area <= max
            }
        }

        // Handle greater than: ">5"
        if trimmed.hasPrefix(">") {
            let numberPart = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            if let value = Double(numberPart) {
                return area > value
            }
        }

        // Handle less than: "<5"
        if trimmed.hasPrefix("<") {
            let numberPart = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            if let value = Double(numberPart) {
                return area < value
            }
        }

        // Handle exact match
        if let value = Double(trimmed) {
            return abs(area - value) < 0.01 // Allow small floating point differences
        }

        return false
    }

    var filteredFieldMaps: [TabulaJob] {
        viewModel.fieldMaps.filter { fieldMap in
            // Customer filter
            if !customerFilter.isEmpty && !fieldMap.customer.localizedCaseInsensitiveContains(customerFilter) {
                return false
            }

            // Contractor filter
            if !contractorFilter.isEmpty && !fieldMap.customer.localizedCaseInsensitiveContains(contractorFilter) {
                return false
            }

            // Order ID filter
            if !orderIdFilter.isEmpty && !"\(fieldMap.id)".contains(orderIdFilter) {
                return false
            }

            // RTS filter
            if rtsFilter != "All" {
                let isRTS = fieldMap.rts
                if rtsFilter == "Yes" && !isRTS {
                    return false
                }
                if rtsFilter == "No" && isRTS {
                    return false
                }
            }

            // Coverage area filter (supports ranges like "2-3", ">5", "<10")
            if !coverageAreaFilter.isEmpty {
                if !matchesAreaFilter(area: fieldMap.area, filter: coverageAreaFilter) {
                    return false
                }
            }

            // Status filter
            if !statusFilter.isEmpty && !fieldMap.status.localizedCaseInsensitiveContains(statusFilter) {
                return false
            }

            // Product filter
            if !productFilter.isEmpty && !fieldMap.productList.localizedCaseInsensitiveContains(productFilter) {
                return false
            }

            // Notes filter
            if !notesFilter.isEmpty && !fieldMap.notes.localizedCaseInsensitiveContains(notesFilter) {
                return false
            }

            // Map address filter
            if !mapAddressFilter.isEmpty && !fieldMap.address.localizedCaseInsensitiveContains(mapAddressFilter) {
                return false
            }

            return true
        }
    }

    private var tableView: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                // Header Row
                HStack(spacing: 0) {
                    if isSelectionMode {
                        TableHeaderCell(title: "", width: 50)
                        Divider()
                    }
                    TableHeaderCell(title: "Customer Name", width: 180)
                    Divider()
                    TableHeaderCell(title: "Contractor Name", width: 180)
                    Divider()
                    TableHeaderCell(title: "Order ID", width: 100)
                    Divider()
                    TableHeaderCell(title: "RTS", width: 80)
                    Divider()
                    TableHeaderCell(title: "Requested Coverage Area (ha)", width: 180)
                    Divider()
                    TableHeaderCell(title: "Status", width: 120)
                    Divider()
                    TableHeaderCell(title: "prod dupli", width: 250)
                    Divider()
                    TableHeaderCell(title: "Notes", width: 200)
                    Divider()
                    TableHeaderCell(title: "Application Rate GPA", width: 150)
                    Divider()
                    TableHeaderCell(title: "Map Address", width: 200)
                }
                .background(Color(.systemGray5))

                // Filter Row
                HStack(spacing: 0) {
                    if isSelectionMode {
                        Color.clear.frame(width: 50)
                        Divider()
                    }
                    FilterTextField(text: $customerFilter, placeholder: "Filter this column...", width: 180)
                    Divider()
                    FilterTextField(text: $contractorFilter, placeholder: "Filter this column...", width: 180)
                    Divider()
                    FilterTextField(text: $orderIdFilter, placeholder: "Filter this column...", width: 100)
                    Divider()

                    // RTS Dropdown
                    Picker("", selection: $rtsFilter) {
                        Text("All").tag("All")
                        Text("Yes").tag("Yes")
                        Text("No").tag("No")
                    }
                    .frame(width: 80)
                    .pickerStyle(MenuPickerStyle())
                    Divider()

                    // Coverage Area Filter (supports: "2-3", ">5", "<10", or exact number)
                    FilterTextField(text: $coverageAreaFilter, placeholder: "e.g. 2-3, >5, <10", width: 180)
                    Divider()

                    FilterTextField(text: $statusFilter, placeholder: "Filter this column...", width: 120)
                    Divider()
                    FilterTextField(text: $productFilter, placeholder: "Filter this column...", width: 250)
                    Divider()
                    FilterTextField(text: $notesFilter, placeholder: "Filter this column...", width: 200)
                    Divider()
                    FilterTextField(text: $applicationRateFilter, placeholder: "Filter this column...", width: 150)
                    Divider()
                    FilterTextField(text: $mapAddressFilter, placeholder: "Filter this column...", width: 200)
                }
                .background(Color(.systemGray6))

                Divider()

                // Data Rows
                ForEach(filteredFieldMaps) { fieldMap in
                    HStack(spacing: 0) {
                        if isSelectionMode {
                            Button(action: {
                                if selectedJobs.contains(fieldMap.id) {
                                    selectedJobs.remove(fieldMap.id)
                                } else {
                                    selectedJobs.insert(fieldMap.id)
                                }
                            }) {
                                Image(systemName: selectedJobs.contains(fieldMap.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedJobs.contains(fieldMap.id) ? .blue : .gray)
                                    .font(.system(size: 20))
                                    .frame(width: 50)
                            }
                            Divider()
                        }

                        TableCell(text: fieldMap.customer, width: 180)
                        Divider()
                        TableCell(text: fieldMap.customer, width: 180) // Contractor same as customer
                        Divider()
                        TableCell(text: "\(fieldMap.id)", width: 100)
                        Divider()
                        TableCell(text: fieldMap.rts ? "Yes" : "No", width: 80, color: fieldMap.rts ? .green : .gray)
                        Divider()
                        TableCell(text: String(format: "%.2f", fieldMap.area), width: 180, alignment: .trailing)
                        Divider()
                        TableCell(text: fieldMap.status.capitalized, width: 120, color: statusColor(for: fieldMap.status))
                        Divider()
                        TableCell(text: fieldMap.productList.isEmpty ? "-" : fieldMap.productList, width: 250)
                        Divider()
                        TableCell(text: fieldMap.notes.isEmpty ? "-" : fieldMap.notes, width: 200)
                        Divider()
                        TableCell(text: "-", width: 150) // Application rate placeholder
                        Divider()
                        TableCell(text: fieldMap.address.isEmpty ? "-" : fieldMap.address, width: 200)
                    }
                    .background(selectedJobs.contains(fieldMap.id) && isSelectionMode ? Color.blue.opacity(0.1) : Color(.systemBackground))

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

struct FilterTextField: View {
    @Binding var text: String
    let placeholder: String
    let width: CGFloat

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 11))
            .textFieldStyle(PlainTextFieldStyle())
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(.systemBackground))
            .cornerRadius(4)
    }
}

// MARK: - ViewModel

@MainActor
class FieldMapsTableViewModel: ObservableObject {
    @Published var fieldMaps: [TabulaJob] = []
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""

    func loadInitialData() async {
        await loadTestData()
    }

    func loadTestData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Load test customer (ID 5429)
            guard let url = URL(string: "http://192.168.68.226:3000/api/field-maps/customer/5429") else {
                throw URLError(.badURL)
            }

            let (data, _) = try await URLSession.shared.data(from: url)
            let apiResponse = try JSONDecoder().decode(JobsAPIResponse.self, from: data)
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
