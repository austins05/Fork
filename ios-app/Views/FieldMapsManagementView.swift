//
//  FieldMapsManagementView.swift
//  Rotorsync - Terralink Integration
//
//  Professional table view with prominent multi-select and reload
//

import SwiftUI
import MapKit

struct FieldMapsManagementView: View {
    @StateObject private var viewModel = FieldMapsViewModel()
    @State private var showingCustomerSearch = false
    @State private var showingMapView = false

    // Multi-select state
    @State private var isSelectionMode = false
    @State private var selectedFieldMaps: Set<Int> = []

    // Column filter state
    @State private var orderIdFilter = ""
    @State private var fieldNameFilter = ""
    @State private var customerFilter = ""
    @State private var statusFilter = "All"
    @State private var rtsFilter = "All"
    @State private var areaFilter = ""
    @State private var cropFilter = ""
    @State private var addressFilter = ""
    @State private var modifiedFilter = ""

    // Sorting state
    @State private var sortColumn: SortColumn = .orderId
    @State private var sortAscending = true

    enum SortColumn {
        case orderId, fieldName, customer, status, rts, area, crop, modified
    }

    var body: some View {
        VStack(spacing: 0) {
            // Action Bar with prominent buttons
            if !viewModel.fieldMaps.isEmpty {
                actionBar
            }

            // Selected customers section
            if !viewModel.selectedCustomers.isEmpty {
                selectedCustomersSection
                    .padding(.bottom, 1)
            }

            // Selection toolbar
            if isSelectionMode && !selectedFieldMaps.isEmpty {
                selectionToolbar
            }

            // Table view
            if viewModel.fieldMaps.isEmpty {
                emptyStateView
            } else {
                tableView
                    .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle("Field Maps")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingCustomerSearch = true }) {
                    Label("Search", systemImage: "magnifyingglass")
                }
            }
        }
        .sheet(isPresented: $showingCustomerSearch) {
            CustomerSearchView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingMapView) {
            FieldMapsMapView(fieldMaps: viewModel.fieldMaps)
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
        }
        .task {
            await viewModel.autoLoadRecentFieldMaps()
        }
    }

    // MARK: - View Components

    private var actionBar: some View {
        HStack(spacing: 12) {
            // Select/Done Button
            Button(action: {
                isSelectionMode.toggle()
                if !isSelectionMode {
                    selectedFieldMaps.removeAll()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isSelectionMode ? "checkmark.circle.fill" : "checkmark.circle")
                    Text(isSelectionMode ? "Done" : "Multi-Select")
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelectionMode ? Color.blue : Color.blue.opacity(0.1))
                .foregroundColor(isSelectionMode ? .white : .blue)
                .cornerRadius(8)
            }

            // Select All Button (only in selection mode)
            if isSelectionMode {
                Button(action: selectAllVisible) {
                    HStack(spacing: 6) {
                        Image(systemName: "checklist")
                        Text("Select All")
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.1))
                    .foregroundColor(.green)
                    .cornerRadius(8)
                }
            }

            Spacer()

            // Map View Button
            Button(action: { showingMapView = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "map.fill")
                    Text("Map")
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.purple.opacity(0.1))
                .foregroundColor(.purple)
                .cornerRadius(8)
            }

            // Reload Button
            Button(action: reloadFieldMaps) {
                HStack(spacing: 6) {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Reload")
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.1))
                .foregroundColor(.orange)
                .cornerRadius(8)
            }
            .disabled(viewModel.isLoading || viewModel.selectedCustomers.isEmpty)
            .opacity(viewModel.selectedCustomers.isEmpty ? 0.5 : 1.0)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separator)),
            alignment: .bottom
        )
    }

    private var selectedCustomersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Selected Customers")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Text("\(viewModel.selectedCustomers.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
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
                    Text(viewModel.isLoading ? "Importing..." : "Import All Field Maps")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(viewModel.selectedCustomers.isEmpty ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(viewModel.selectedCustomers.isEmpty || viewModel.isLoading)
        }
        .padding()
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private var selectionToolbar: some View {
        HStack {
            Text("\(selectedFieldMaps.count) field\(selectedFieldMaps.count == 1 ? "" : "s") selected")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            Spacer()

            Button(action: {
                selectedFieldMaps.removeAll()
            }) {
                Text("Clear")
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(6)
            }

            Button(action: importSelectedFields) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc.fill")
                    Text("Bulk Import")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(8)
                .shadow(color: Color.blue.opacity(0.3), radius: 3, x: 0, y: 2)
            }
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.05), Color.blue.opacity(0.02)]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.blue.opacity(0.3)),
            alignment: .bottom
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "map")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))

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
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tableView: some View {
        VStack(spacing: 0) {
            // Table Header
            tableHeader

            // Filter Row
            filterRow

            // Table Content
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sortedAndFilteredFieldMaps.enumerated()), id: \.element.id) { index, fieldMap in
                        TableRow(
                            fieldMap: fieldMap.fieldMap,
                            isSelectionMode: isSelectionMode,
                            isSelected: selectedFieldMaps.contains(fieldMap.id),
                            isEvenRow: index % 2 == 0,
                            onToggleSelection: {
                                if selectedFieldMaps.contains(fieldMap.id) {
                                    selectedFieldMaps.remove(fieldMap.id)
                                } else {
                                    selectedFieldMaps.insert(fieldMap.id)
                                }
                            },
                            onView: {
                                viewModel.selectedFieldMap = fieldMap
                                showingMapView = true
                            }
                        )
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var tableHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                if isSelectionMode {
                    Button(action: {
                        if selectedFieldMaps.count == sortedAndFilteredFieldMaps.count {
                            selectedFieldMaps.removeAll()
                        } else {
                            selectAllVisible()
                        }
                    }) {
                        Image(systemName: selectedFieldMaps.count == sortedAndFilteredFieldMaps.count ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedFieldMaps.count == sortedAndFilteredFieldMaps.count ? .blue : .gray)
                            .font(.body)
                    }
                    .frame(width: 40)
                    .buttonStyle(PlainButtonStyle())
                }

                SortableHeaderCell(
                    title: "Order ID",
                    width: 80,
                    column: .orderId,
                    currentSort: sortColumn,
                    ascending: sortAscending,
                    onSort: { sortColumn = $0; sortAscending.toggle() }
                )

                SortableHeaderCell(
                    title: "Field Name",
                    width: 150,
                    column: .fieldName,
                    currentSort: sortColumn,
                    ascending: sortAscending,
                    onSort: { sortColumn = $0; sortAscending.toggle() }
                )

                SortableHeaderCell(
                    title: "Customer",
                    width: 150,
                    column: .customer,
                    currentSort: sortColumn,
                    ascending: sortAscending,
                    onSort: { sortColumn = $0; sortAscending.toggle() }
                )

                SortableHeaderCell(
                    title: "Status",
                    width: 100,
                    column: .status,
                    currentSort: sortColumn,
                    ascending: sortAscending,
                    onSort: { sortColumn = $0; sortAscending.toggle() }
                )

                SortableHeaderCell(
                    title: "Rts Yes",
                    width: 80,
                    column: .rts,
                    currentSort: sortColumn,
                    ascending: sortAscending,
                    onSort: { sortColumn = $0; sortAscending.toggle() }
                )

                SortableHeaderCell(
                    title: "Area (ac)",
                    width: 90,
                    column: .area,
                    currentSort: sortColumn,
                    ascending: sortAscending,
                    onSort: { sortColumn = $0; sortAscending.toggle() }
                )

                SortableHeaderCell(
                    title: "Crop",
                    width: 120,
                    column: .crop,
                    currentSort: sortColumn,
                    ascending: sortAscending,
                    onSort: { sortColumn = $0; sortAscending.toggle() }
                )

                HeaderCell(title: "Address", width: 200)

                SortableHeaderCell(
                    title: "Modified",
                    width: 100,
                    column: .modified,
                    currentSort: sortColumn,
                    ascending: sortAscending,
                    onSort: { sortColumn = $0; sortAscending.toggle() }
                )

                HeaderCell(title: "Actions", width: 100)
            }
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color(.systemGray6), Color(.systemGray5)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(.separator)),
                alignment: .bottom
            )
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                if isSelectionMode {
                    Text("")
                        .frame(width: 40)
                }

                FilterTextField(text: $orderIdFilter, placeholder: "Filter...", width: 80)
                FilterTextField(text: $fieldNameFilter, placeholder: "Filter...", width: 150)
                FilterTextField(text: $customerFilter, placeholder: "Filter...", width: 150)

                FilterDropdown(
                    selection: $statusFilter,
                    options: ["All"] + uniqueStatuses,
                    width: 100
                )

                FilterDropdown(
                    selection: $rtsFilter,
                    options: ["All", "Yes", "No"],
                    width: 80
                )

                FilterTextField(text: $areaFilter, placeholder: "Filter...", width: 90)
                FilterTextField(text: $cropFilter, placeholder: "Filter...", width: 120)
                FilterTextField(text: $addressFilter, placeholder: "Filter...", width: 200)
                FilterTextField(text: $modifiedFilter, placeholder: "Filter...", width: 100)

                Text("")
                    .frame(width: 100)
            }
            .padding(.vertical, 8)
            .background(Color(.systemGray6).opacity(0.5))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(.separator)),
                alignment: .bottom
            )
        }
    }

    private var uniqueStatuses: [String] {
        let statuses = Set(viewModel.fieldMaps.map { $0.fieldMap.status.capitalized })
        return Array(statuses).sorted()
    }

    private var filteredFieldMaps: [FieldMapWithCustomer] {
        viewModel.fieldMaps.filter { fieldMap in
            let fm = fieldMap.fieldMap

            if !orderIdFilter.isEmpty && !"\(fm.id)".contains(orderIdFilter) {
                return false
            }
            if !fieldNameFilter.isEmpty && !fm.name.localizedCaseInsensitiveContains(fieldNameFilter) {
                return false
            }
            if !customerFilter.isEmpty && !fm.customer.localizedCaseInsensitiveContains(customerFilter) {
                return false
            }
            if statusFilter != "All" && fm.status.capitalized != statusFilter {
                return false
            }

            // RTS filter
            if rtsFilter != "All" {
                let rtsValue = fm.rts ?? false
                if rtsFilter == "Yes" && !rtsValue {
                    return false
                }
                if rtsFilter == "No" && rtsValue {
                    return false
                }
            }

            if !areaFilter.isEmpty && !String(format: "%.1f", fm.area).contains(areaFilter) {
                return false
            }
            if !cropFilter.isEmpty {
                if let crop = fm.productList {
                    if !crop.localizedCaseInsensitiveContains(cropFilter) {
                        return false
                    }
                } else {
                    return false
                }
            }
            if !addressFilter.isEmpty {
                if let address = fm.address {
                    if !address.localizedCaseInsensitiveContains(addressFilter) {
                        return false
                    }
                } else {
                    return false
                }
            }
            if !modifiedFilter.isEmpty {
                if let modDate = fm.modifiedDate {
                    let date = Date(timeIntervalSince1970: TimeInterval(modDate))
                    let formatter = DateFormatter()
                    formatter.dateStyle = .short
                    let dateString = formatter.string(from: date)
                    if !dateString.contains(modifiedFilter) {
                        return false
                    }
                } else {
                    return false
                }
            }

            return true
        }
    }

    private var sortedAndFilteredFieldMaps: [FieldMapWithCustomer] {
        filteredFieldMaps.sorted { lhs, rhs in
            let ascending = sortAscending
            switch sortColumn {
            case .orderId:
                return ascending ? lhs.fieldMap.id < rhs.fieldMap.id : lhs.fieldMap.id > rhs.fieldMap.id
            case .fieldName:
                return ascending ? lhs.fieldMap.name < rhs.fieldMap.name : lhs.fieldMap.name > rhs.fieldMap.name
            case .customer:
                return ascending ? lhs.fieldMap.customer < rhs.fieldMap.customer : lhs.fieldMap.customer > rhs.fieldMap.customer
            case .status:
                return ascending ? lhs.fieldMap.status < rhs.fieldMap.status : lhs.fieldMap.status > rhs.fieldMap.status
            case .rts:
                let lhsRts = lhs.fieldMap.rts ?? false
                let rhsRts = rhs.fieldMap.rts ?? false
                return ascending ? (lhsRts ? 0 : 1) < (rhsRts ? 0 : 1) : (lhsRts ? 0 : 1) > (rhsRts ? 0 : 1)
            case .area:
                return ascending ? lhs.fieldMap.area < rhs.fieldMap.area : lhs.fieldMap.area > rhs.fieldMap.area
            case .crop:
                let lhsCrop = lhs.fieldMap.productList ?? ""
                let rhsCrop = rhs.fieldMap.productList ?? ""
                return ascending ? lhsCrop < rhsCrop : lhsCrop > rhsCrop
            case .modified:
                let lhsDate = lhs.fieldMap.modifiedDate ?? 0
                let rhsDate = rhs.fieldMap.modifiedDate ?? 0
                return ascending ? lhsDate < rhsDate : lhsDate > rhsDate
            }
        }
    }

    private func selectAllVisible() {
        for fieldMap in sortedAndFilteredFieldMaps {
            selectedFieldMaps.insert(fieldMap.id)
        }
    }

    private func importSelectedFields() {
        print("Bulk importing \(selectedFieldMaps.count) selected fields to Rotorsync")
        // TODO: Implement actual bulk import to Rotorsync app
        selectedFieldMaps.removeAll()
        isSelectionMode = false
    }

    private func reloadFieldMaps() {
        Task {
            await viewModel.importFieldMaps()
        }
    }
}

// MARK: - Filter Components

struct FilterTextField: View {
    @Binding var text: String
    let placeholder: String
    let width: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            TextField(placeholder, text: $text)
                .font(.caption2)
                .textFieldStyle(PlainTextFieldStyle())

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: width)
        .background(Color(.systemBackground))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(.separator), lineWidth: 1)
        )
        .padding(.horizontal, 4)
    }
}

struct FilterDropdown: View {
    @Binding var selection: String
    let options: [String]
    let width: CGFloat

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(action: { selection = option }) {
                    HStack {
                        Text(option)
                        if selection == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selection)
                    .font(.caption2)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: width)
            .background(Color(.systemBackground))
            .foregroundColor(.primary)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(.separator), lineWidth: 1)
            )
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Table Components

struct HeaderCell: View {
    let title: String
    let width: CGFloat

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 8)
    }
}

struct SortableHeaderCell: View {
    let title: String
    let width: CGFloat
    let column: FieldMapsManagementView.SortColumn
    let currentSort: FieldMapsManagementView.SortColumn
    let ascending: Bool
    let onSort: (FieldMapsManagementView.SortColumn) -> Void

    var body: some View {
        Button(action: { onSort(column) }) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                if currentSort == column {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct TableRow: View {
    let fieldMap: FieldMap
    let isSelectionMode: Bool
    let isSelected: Bool
    let isEvenRow: Bool
    let onToggleSelection: () -> Void
    let onView: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                if isSelectionMode {
                    Button(action: onToggleSelection) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? .blue : .gray)
                            .font(.body)
                    }
                    .frame(width: 40)
                    .buttonStyle(PlainButtonStyle())
                }

                CellText(text: "\(fieldMap.id)", width: 80, isBold: false)
                CellText(text: fieldMap.name, width: 150, isBold: true)
                CellText(text: fieldMap.customer, width: 150, isBold: false)

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(fieldMap.status.capitalized)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .frame(width: 100, alignment: .leading)
                .padding(.horizontal, 8)

                // RTS Yes/No
                HStack(spacing: 4) {
                    if let rts = fieldMap.rts, rts {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    Text((fieldMap.rts ?? false) ? "Yes" : "No")
                        .font(.caption)
                }
                .frame(width: 80, alignment: .leading)
                .padding(.horizontal, 8)

                CellText(text: String(format: "%.1f", fieldMap.area), width: 90, isBold: false)
                CellText(text: fieldMap.productList ?? "-", width: 120, isBold: false)
                CellText(text: fieldMap.address ?? "-", width: 200, isBold: false)
                CellText(text: formattedDate, width: 100, isBold: false)

                HStack(spacing: 8) {
                    Button(action: onView) {
                        Image(systemName: "map.fill")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.blue)
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: {}) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.green)
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .frame(width: 100, alignment: .leading)
                .padding(.horizontal, 8)
            }
            .padding(.vertical, 10)
            .background(isEvenRow ? Color(.systemGray6).opacity(0.3) : Color(.systemBackground))
        }
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separator).opacity(0.3)),
            alignment: .bottom
        )
    }

    private var statusColor: Color {
        switch fieldMap.status.lowercased() {
        case "complete", "completed":
            return .green
        case "in progress", "inprogress":
            return .orange
        case "pending":
            return .yellow
        default:
            return .gray
        }
    }

    private var formattedDate: String {
        guard let modDate = fieldMap.modifiedDate else { return "-" }
        let date = Date(timeIntervalSince1970: TimeInterval(modDate))
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

struct CellText: View {
    let text: String
    let width: CGFloat
    let isBold: Bool

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(isBold ? .medium : .regular)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 8)
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
                .fontWeight(.medium)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.15), Color.blue.opacity(0.1)]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .foregroundColor(.blue)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Preview

struct FieldMapsManagementView_Previews: PreviewProvider {
    static var previews: some View {
        FieldMapsManagementView()
    }
}
