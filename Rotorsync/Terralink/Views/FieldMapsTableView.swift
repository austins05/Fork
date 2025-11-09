//
//  FieldMapsTableView.swift
//  Rotorsync - Full-screen table view for Tabula field maps
//

import SwiftUI
import Combine
import CoreLocation

struct FieldMapsTableView: View {
    @StateObject private var viewModel = FieldMapsTableViewModel()
    @State private var selectedJobs: Set<Int> = []
    @State private var hasLoadedData = false

    // Import progress tracking
    @State private var isImporting = false
    @State private var importProgress = 0
    @State private var importTotal = 0
    @State private var showDashSettings = false
    @State private var showColorWarning = false
    @State private var colorWarningMessage = ""

    // Filter states
    @State private var customerFilter = ""
    @State private var contractorFilter = ""
    @State private var orderIdFilter = ""
    @State private var rtsFilter = "All"
    @State private var coverageAreaFilter = ""
    @State private var statusFilter = "All"
    @State private var productFilter = ""
    @State private var notesFilter = ""
    @State private var applicationRateFilter = ""
    @State private var mapAddressFilter = ""

    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    // Selection toolbar - Always visible
                    selectionToolbar

                    if viewModel.isLoading {
                        ProgressView("Loading jobs...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.fieldMaps.isEmpty {
                        emptyStateView
                    } else {
                        tableView
                    }
                }

                // Import progress overlay
                if isImporting {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        Text("Importing Fields")
                            .font(.headline)

                        ProgressView(value: Double(importProgress), total: Double(importTotal))
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(width: 250)

                        Text("\(importProgress) of \(importTotal) downloaded")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(24)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(radius: 10)
                }
            }
            .navigationTitle("Field Maps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        SharedFieldStorage.shared.clearAllFields()
                    }) {
                        Label("Clear All Fields", systemImage: "trash.fill")
                            .foregroundColor(.red)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            hasLoadedData = true
                            await viewModel.refreshData()
                        }
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .task {
                guard !hasLoadedData else { return }
                hasLoadedData = true
                await viewModel.loadInitialData()
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage)
            }
            .alert("Color Conflict Warning", isPresented: $showColorWarning) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(colorWarningMessage)
            }
            .sheet(isPresented: $showDashSettings) {
                TerralinkSettingsView()
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
                Task {
                    await importSelectedToMap()
                }
            }) {
                HStack {
                    Image(systemName: "map.fill")
                    Text("Import to Map")
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(viewModel.isLoading)

            Button(action: {
                // Reset all filters
                customerFilter = ""
                contractorFilter = ""
                orderIdFilter = ""
                rtsFilter = "All"
                coverageAreaFilter = ""
                statusFilter = "All"
                productFilter = ""
                notesFilter = ""
                applicationRateFilter = ""
                mapAddressFilter = ""
            }) {
                Text("Reset Filters")
                    .font(.subheadline)
            }
            .padding(.leading, 8)

            Button(action: {
                selectedJobs.removeAll()
            }) {
                Text("Clear")
                    .font(.subheadline)
            }
            .padding(.leading, 8)

            Button(action: {
                FieldGeometryCache.shared.clearCache()
                print("🗑️ Cache cleared manually")
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "trash.fill")
                    Text("Clear Cache")
                        .font(.subheadline)
                }
            }
            .padding(.leading, 8)
            .foregroundColor(.red)

            Button(action: {
                showDashSettings = true
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
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
            if !contractorFilter.isEmpty {
                if let contractor = fieldMap.contractor, !contractor.localizedCaseInsensitiveContains(contractorFilter) {
                    return false
                } else if fieldMap.contractor == nil {
                    return false
                }
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
            if statusFilter != "All" && !statusFilter.isEmpty && !fieldMap.status.localizedCaseInsensitiveContains(statusFilter) {
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

    // Auto-suggest lists for filters
    var customerSuggestions: [String] {
        Array(Set(viewModel.fieldMaps.map { $0.customer })).filter { !$0.isEmpty }
    }

    var contractorSuggestions: [String] {
        Array(Set(viewModel.fieldMaps.compactMap { $0.contractor })).filter { !$0.isEmpty }
    }

    var statusSuggestions: [String] {
        Array(Set(viewModel.fieldMaps.map { $0.status })).filter { !$0.isEmpty }
    }

    var productSuggestions: [String] {
        Array(Set(viewModel.fieldMaps.map { $0.productList })).filter { !$0.isEmpty }
    }

    var addressSuggestions: [String] {
        Array(Set(viewModel.fieldMaps.map { $0.address })).filter { !$0.isEmpty }
    }

    private var tableView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
                .frame(height: 16)

            // Synchronized horizontal scrolling for all sections
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header Row - ANCHORED
                    HStack(spacing: 0) {
                    // Select All button
                    Button(action: {
                        if selectedJobs.count == filteredFieldMaps.count && !filteredFieldMaps.isEmpty {
                            selectedJobs.removeAll()
                        } else {
                            selectedJobs = Set(filteredFieldMaps.map { $0.id })
                            // Download geometry for all selected fields
                            viewModel.downloadGeometryBatch(for: filteredFieldMaps)
                        }
                    }) {
                        Image(systemName: selectedJobs.count == filteredFieldMaps.count && !filteredFieldMaps.isEmpty ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedJobs.count == filteredFieldMaps.count && !filteredFieldMaps.isEmpty ? .blue : .gray)
                            .font(.system(size: 20))
                            .frame(width: 50)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                    }
                    Divider()
                    TableHeaderCell(title: "Customer Name", width: 180)
                    Divider()
                    TableHeaderCell(title: "Contractor Name", width: 180)
                    Divider()
                    TableHeaderCell(title: "Order ID", width: 100)
                    Divider()
                    TableHeaderCell(title: "RTS", width: 80)
                    Divider()
                    TableHeaderCell(title: "Req. Area", width: 100)
                    Divider()
                    TableHeaderCell(title: "Status", width: 120)
                    Divider()
                    TableHeaderCell(title: "Prod Dupli", width: 120)
                    Divider()
                    TableHeaderCell(title: "Notes", width: 200)
                    Divider()
                    TableHeaderCell(title: "App Rate", width: 100)
                    Divider()
                    TableHeaderCell(title: "Map Address", width: 200)
                }
                .background(Color(.systemGray5))
                .frame(height: 44)

                Divider()

                // Filter Row - ANCHORED
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: 50, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    Divider()
                    FilterTextField(text: $customerFilter, placeholder: "Filter this column...", width: 180, suggestions: customerSuggestions)
                    Divider()
                    FilterTextField(text: $contractorFilter, placeholder: "Filter this column...", width: 180, suggestions: contractorSuggestions)
                    Divider()
                    FilterTextField(text: $orderIdFilter, placeholder: "Filter this column...", width: 100)
                    Divider()
                    FilterDropdown(selection: $rtsFilter, options: ["All", "Yes", "No"], width: 80, colorMap: ["Yes": .green, "No": .red, "All": .primary])
                    Divider()
                    FilterTextField(text: $coverageAreaFilter, placeholder: "Filter this column...", width: 100)
                    Divider()
                    FilterDropdown(selection: $statusFilter, options: ["All", "Placed", "Complete", "Returned"], width: 120, colorMap: ["Complete": .green, "Placed": .blue, "Returned": .orange, "All": .primary])
                    Divider()
                    FilterTextField(text: $productFilter, placeholder: "Filter this column...", width: 120, suggestions: productSuggestions)
                    Divider()
                    FilterTextField(text: $notesFilter, placeholder: "Filter this column...", width: 200)
                    Divider()
                    FilterTextField(text: $applicationRateFilter, placeholder: "Filter this column...", width: 100)
                    Divider()
                    FilterTextField(text: $mapAddressFilter, placeholder: "Filter this column...", width: 200, suggestions: addressSuggestions)
                }
                .background(Color(.systemGray6))
                .frame(height: 40)

                // Data Rows - SCROLLABLE (vertical only)
                ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredFieldMaps) { fieldMap in
                    HStack(spacing: 0) {
                        Button(action: {
                            if selectedJobs.contains(fieldMap.id) {
                                selectedJobs.remove(fieldMap.id)
                            } else {
                                selectedJobs.insert(fieldMap.id)
                                // Download geometry in background when selected
                                viewModel.downloadGeometry(for: fieldMap)
                            }
                        }) {
                            Image(systemName: selectedJobs.contains(fieldMap.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedJobs.contains(fieldMap.id) ? .blue : .gray)
                                .font(.system(size: 20))
                                .frame(width: 50)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 10)
                        }
                        Divider()

                        TableCell(text: fieldMap.customer, width: 180)
                        Divider()
                        TableCell(text: fieldMap.contractor ?? "", width: 180)
                        Divider()
                        TableCell(text: "\(fieldMap.id)", width: 100)
                        Divider()
                        TableCell(text: fieldMap.rts ? "Yes" : "No", width: 80, color: fieldMap.rts ? .green : .red)
                        Divider()
                        TableCell(text: String(format: "%.2f", fieldMap.area * 2.47105), width: 100, alignment: .trailing)
                        Divider()
                        TableCell(text: fieldMap.status.capitalized, width: 120, color: statusColor(for: fieldMap.status))
                        Divider()
                        TableCell(text: fieldMap.prodDupli ?? "-", width: 120)
                        Divider()
                        TableCell(text: fieldMap.notes.isEmpty ? "-" : fieldMap.notes, width: 200)
                        Divider()
                        TableCell(text: "-", width: 100) // Application rate placeholder
                        Divider()
                        TableCell(text: fieldMap.address.isEmpty ? "-" : fieldMap.address, width: 200)
                    }
                    .background(selectedJobs.contains(fieldMap.id) ? Color.blue.opacity(0.1) : Color(.systemBackground))

                    Divider()
                    }
                }
                }
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

    func importSelectedToMap() async {
        guard !selectedJobs.isEmpty else { return }

        await MainActor.run {
            isImporting = true
            importProgress = 0
            importTotal = selectedJobs.count
        }
        defer {
            Task { @MainActor in
                isImporting = false
            }
        }

        do {
            var fields: [FieldData] = []
            var errors: [String] = []

            for jobId in selectedJobs {
                guard let job = viewModel.fieldMaps.first(where: { $0.id == jobId }) else {
                    errors.append("Job \(jobId) not found")
                    await MainActor.run { importProgress += 1 }
                    continue
                }

                // Try cache first for instant import
                print("🔍 Checking cache for job \(jobId)...")
                if let cached = FieldGeometryCache.shared.getCachedGeometry(fieldId: jobId) {
                    let boundaries = cached.boundaries  // Multiple boundaries
                    let sprayLines = cached.sprayLines
                    print("✅ CACHE HIT for job \(jobId) - \(boundaries.count) boundaries, \(sprayLines?.count ?? 0) spray lines")

                    // Convert colors from Tabula
                    let colorMap: [String: String] = [
                        "red": "#FF0000", "orange": "#FF8C00", "yellow": "#FFFF00",
                        "green": "#00FF00", "teal": "#00FFFF", "blue": "#0000FF",
                        "purple": "#9966FF", "pink": "#FF69B4", "magenta": "#FF00FF",
                        "gray": "#404040", "grey": "#404040", "black": "#000000", "white": "#FFFFFF"
                    ]

                    // Fill color from 'color' field
                    var fillColor = ""
                    if let colorName = job.color {
                        let name = colorName.lowercased().trimmingCharacters(in: CharacterSet.whitespaces)
                        if name.hasPrefix("#") {
                            fillColor = colorName
                        } else if let hexColor = colorMap[name] {
                            fillColor = hexColor
                        }
                    }

                    // Boundary color from 'boundaryColor' field, fallback to fill color
                    var strokeColor: String? = nil
                    print("🎨 Job \(jobId): boundaryColor field = '\(job.boundaryColor ?? "nil")'")
                    if let boundaryColorName = job.boundaryColor, !boundaryColorName.isEmpty {
                        let name = boundaryColorName.lowercased().trimmingCharacters(in: CharacterSet.whitespaces)
                        print("🎨 Processing boundaryColor '\(boundaryColorName)' -> lowercased: '\(name)'")
                        if name.hasPrefix("#") {
                            strokeColor = boundaryColorName
                            print("🎨 Using hex boundary: \(boundaryColorName)")
                        } else if let hexColor = colorMap[name] {
                            strokeColor = hexColor
                            print("🎨 Converted '\(name)' to hex: \(hexColor)")
                        } else {
                            print("❌ Could not find color '\(name)' in colorMap")
                        }
                    } else {
                        print("🎨 No boundaryColor set, will use fill color")
                    }
                    print("🎨 Final strokeColor: \(strokeColor ?? "nil")")


                    // Check if contractor has dash color setting
                    var contractorDash: String? = nil
                    if let contractorName = job.contractor, !contractorName.isEmpty {
                        contractorDash = ContractorDashSettingsManager.shared.getDashColor(for: contractorName)
                        print("🔍 Contractor '\(contractorName)' has dash color: \(contractorDash ?? "none")")
                    }

                    // Check if boundary and dash colors match
                    if let dash = contractorDash {
                        // Compare with boundary color (or fill color if no boundary color)
                        let actualBoundary = strokeColor ?? fillColor
                        print("🔍 Checking colors - boundary: '\(actualBoundary)', dash: '\(dash)'")

                        if !actualBoundary.isEmpty && dash.lowercased() == actualBoundary.lowercased() {
                            print("🚨 COLOR MATCH DETECTED!")
                            await MainActor.run {
                                colorWarningMessage = "⚠️ Order #\(jobId) (\(job.name))\n\nBoundary color and contractor dash color are both \(dash).\n\nThe contractor dash pattern won't be visible! Please change one of the colors."
                                showColorWarning = true
                            }
                            print("⚠️ COLOR CONFLICT: Job \(jobId) - boundary=\(actualBoundary), dash=\(dash)")
                        } else {
                            print("✅ Colors are different - boundary: \(actualBoundary), dash: \(dash)")
                        }
                    } else {
                        print("ℹ️ No contractor dash color set for job \(jobId)")
                    }

                    // Create a field entry for each boundary polygon
                    for (index, boundary) in boundaries.enumerated() {
                        let fieldName = boundaries.count > 1 ? "\(job.name) (\(index + 1))" : job.name
                        let fieldData = FieldData(
                            id: job.id + index * 10000,  // Unique ID for each polygon
                            name: fieldName,
                            coordinates: boundary,
                            acres: job.area * 2.47105 / Double(boundaries.count),  // Divide area
                            color: fillColor,  // Fill color
                            boundaryColor: strokeColor,  // Stroke color (nil means use fill color)
                            contractorDashColor: contractorDash,  // Dashed border for contractor
                            category: job.status,
                            application: nil,
                            description: nil,
                            prodDupli: job.prodDupli,
                            productList: job.productList,
                            notes: job.notes,
                            address: job.address,
                            source: .tabula,
                            workedCoordinates: sprayLines
                        )
                        fields.append(fieldData)
                    }
                    print("⚡ INSTANT: Used cached geometry for job \(jobId) (\(boundaries.count) boundaries)")
                    await MainActor.run { importProgress += 1 }
                    continue
                }

                // Fall back to network if not cached
                print("❌ CACHE MISS for job \(jobId) - fetching from network")


                // Fetch geometry from backend
                let url = URL(string: "http://192.168.68.226:3000/api/field-maps/\(jobId)/geometry?type=requested")!
                let (data, response) = try await URLSession.shared.data(from: url)

                // Check HTTP status
                if let httpResponse = response as? HTTPURLResponse {
                    print("📡 Job \(jobId) response: \(httpResponse.statusCode)")
                    if httpResponse.statusCode != 200 {
                        if let errorMsg = String(data: data, encoding: .utf8) {
                            print("❌ Error response: \(errorMsg)")
                            errors.append("Job \(jobId): HTTP \(httpResponse.statusCode)")
                        }
                        await MainActor.run { importProgress += 1 }
                        continue
                    }
                }

                // Debug: Print raw response
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📦 Raw response for job \(jobId): \(jsonString.prefix(200))...")
                }

                // Parse GeoJSON - API returns: {success, data: {features: [{geometry, properties}]}}
                guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    errors.append("Job \(jobId): Invalid JSON")
                    print("❌ Failed to parse JSON for job \(jobId)")
                    await MainActor.run { importProgress += 1 }
                    continue
                }

                guard let responseData = response["data"] as? [String: Any] else {
                    errors.append("Job \(jobId): Missing data field")
                    print("❌ No 'data' field in response for job \(jobId)")
                    await MainActor.run { importProgress += 1 }
                    continue
                }

                guard let features = responseData["features"] as? [[String: Any]], !features.isEmpty else {
                    errors.append("Job \(jobId): No features found")
                    print("❌ No features in data for job \(jobId)")
                    await MainActor.run { importProgress += 1 }
                    continue
                }

                // Parse ALL boundary features
                var boundaryCoordinates: [[CLLocationCoordinate2D]] = []
                for feature in features {
                    guard let geometry = feature["geometry"] as? [String: Any],
                          let coords = parseGeoJSONCoordinates(geometry) else {
                        continue
                    }
                    boundaryCoordinates.append(coords)
                }

                if boundaryCoordinates.isEmpty {
                    errors.append("Job \(jobId): Failed to parse any coordinates")
                    print("❌ Failed to parse coordinates for job \(jobId)")
                    await MainActor.run { importProgress += 1 }
                    continue
                }

                // Convert colors from Tabula
                let colorMap: [String: String] = [
                    "red": "#FF0000",
                    "orange": "#FF8C00",
                    "yellow": "#FFFF00",
                    "green": "#00FF00",
                    "teal": "#00FFFF",
                    "blue": "#0000FF",
                    "purple": "#9966FF",
                    "pink": "#FF69B4",
                    "magenta": "#FF00FF",
                    "gray": "#404040",
                    "grey": "#404040",
                    "black": "#000000",
                    "white": "#FFFFFF"
                ]

                // Fill color from 'color' field
                var fillColor = ""
                if let colorName = job.color {
                    let name = colorName.lowercased().trimmingCharacters(in: CharacterSet.whitespaces)
                    if name.hasPrefix("#") {
                        fillColor = colorName
                    } else if let hexColor = colorMap[name] {
                        fillColor = hexColor
                    }
                }

                // Boundary color from 'boundaryColor' field, fallback to fill color
                var strokeColor: String? = nil
                print("🎨 Job \(jobId): boundaryColor field = '\(job.boundaryColor ?? "nil")'")
                if let boundaryColorName = job.boundaryColor, !boundaryColorName.isEmpty {
                    let name = boundaryColorName.lowercased().trimmingCharacters(in: CharacterSet.whitespaces)
                    print("🎨 Processing boundaryColor '\(boundaryColorName)' -> lowercased: '\(name)'")
                    if name.hasPrefix("#") {
                        strokeColor = boundaryColorName
                        print("🎨 Using hex boundary: \(boundaryColorName)")
                    } else if let hexColor = colorMap[name] {
                        strokeColor = hexColor
                        print("🎨 Converted '\(name)' to hex: \(hexColor)")
                    } else {
                        print("❌ Could not find color '\(name)' in colorMap")
                    }
                } else {
                    print("🎨 No boundaryColor set, will use fill color")
                }
                print("🎨 Final strokeColor: \(strokeColor ?? "nil")")
                print("🎨 Import: Job \(job.id) - fill: '\(job.color ?? "none")' -> \(fillColor), boundary: '\(job.boundaryColor ?? "none")' -> \(strokeColor ?? "use fill")")

                // Fetch worked geometry (spray lines) - fetch ALL features
                var workedPolygons: [[CLLocationCoordinate2D]]? = nil
                let workedURLString = "http://192.168.68.226:3000/api/field-maps/\(job.id)/geometry?type=worked-detailed"
                print("🔍 REQUESTING URL: \(workedURLString)")
                if let workedURL = URL(string: workedURLString) {
                    do {
                        print("✅ URL created successfully, making request...")
                        let (workedData, workedResponse) = try await URLSession.shared.data(from: workedURL)
                        if let httpResponse = workedResponse as? HTTPURLResponse {
                            print("📡 Response status: \(httpResponse.statusCode)")
                        }
                        if let httpResponse = workedResponse as? HTTPURLResponse, httpResponse.statusCode == 200 {
                            let geometryResponse = try JSONDecoder().decode(GeometryAPIResponse.self, from: workedData)
                            // Fetch ALL features, not just the first one!
                            let allPolygons = geometryResponse.data.features.compactMap { $0.geometry.mapCoordinates }
                            if !allPolygons.isEmpty {
                                workedPolygons = allPolygons
                                print("✈️ Fetched worked geometry for job \(job.id): \(allPolygons.count) polygons with \(allPolygons.map{$0.count}.reduce(0,+)) total coords")
                            }
                        }
                    } catch {
                        print("⚠️ No worked geometry for job \(job.id): \(error.localizedDescription)")
                    }
                }


                // Check if contractor has dash color setting
                var contractorDash: String? = nil
                if let contractorName = job.contractor, !contractorName.isEmpty {
                    contractorDash = ContractorDashSettingsManager.shared.getDashColor(for: contractorName)
                    print("🔍 Contractor '\(contractorName)' has dash color: \(contractorDash ?? "none")")
                }

                // Check if boundary and dash colors match
                if let dash = contractorDash {
                    // Compare with boundary color (or fill color if no boundary color)
                    let actualBoundary = strokeColor ?? fillColor
                    print("🔍 Checking colors - boundary: '\(actualBoundary)', dash: '\(dash)'")

                    if !actualBoundary.isEmpty && dash.lowercased() == actualBoundary.lowercased() {
                        print("🚨 COLOR MATCH DETECTED!")
                        await MainActor.run {
                            colorWarningMessage = "⚠️ Order #\(jobId) (\(job.name))\n\nBoundary color and contractor dash color are both \(dash).\n\nThe contractor dash pattern won't be visible! Please change one of the colors."
                            showColorWarning = true
                        }
                        print("⚠️ COLOR CONFLICT: Job \(jobId) - boundary=\(actualBoundary), dash=\(dash)")
                    } else {
                        print("✅ Colors are different - boundary: \(actualBoundary), dash: \(dash)")
                    }
                } else {
                    print("ℹ️ No contractor dash color set for job \(jobId)")
                }

                // Create a field entry for each boundary polygon
                for (index, boundaryCoords) in boundaryCoordinates.enumerated() {
                    let fieldName = boundaryCoordinates.count > 1 ? "\(job.name) (\(index + 1))" : job.name
                    let fieldData = FieldData(
                        id: job.id + index * 10000,  // Unique ID for each polygon
                        name: fieldName,
                        coordinates: boundaryCoords,
                        acres: job.area * 2.47105 / Double(boundaryCoordinates.count), // Divide area
                        color: fillColor,  // Fill color
                        boundaryColor: strokeColor,  // Stroke color (nil means use fill color)
                        contractorDashColor: contractorDash,  // Dashed border for contractor
                        category: job.status,
                        application: nil,
                        description: nil,
                        prodDupli: job.prodDupli,
                        productList: job.productList,
                        notes: job.notes,
                        address: job.address,
                        source: .tabula,
                        workedCoordinates: workedPolygons
                    )
                    fields.append(fieldData)
                }
                print("✅ Successfully parsed job \(jobId) - \(boundaryCoordinates.count) boundaries")

                // Update progress
                await MainActor.run {
                    importProgress += 1
                }
            }

            // Import to map using shared storage
            await MainActor.run {
                if fields.isEmpty {
                    viewModel.errorMessage = "Failed to import any fields. Errors: \(errors.joined(separator: ", "))"
                    viewModel.showError = true
                } else {
                    SharedFieldStorage.shared.addFieldsForImport(fields)
                    print("✅ Successfully imported \(fields.count) field(s) to Map tab")
                    // Clear selection after successful import
                    selectedJobs.removeAll()
                }
            }

        } catch {
            await MainActor.run {
                viewModel.errorMessage = "Failed to import: \(error.localizedDescription)"
                viewModel.showError = true
            }
        }
    }

    func parseGeoJSONCoordinates(_ geometry: [String: Any]) -> [CLLocationCoordinate2D]? {
        guard let type = geometry["type"] as? String else { return nil }

        if type == "Polygon" {
            guard let coords = geometry["coordinates"] as? [[[Double]]] else { return nil }
            // First ring is outer boundary
            if let ring = coords.first {
                return ring.compactMap { coord in
                    guard coord.count >= 2 else { return nil }
                    return CLLocationCoordinate2D(latitude: coord[1], longitude: coord[0])
                }
            }
        } else if type == "MultiPolygon" {
            guard let coords = geometry["coordinates"] as? [[[[Double]]]] else { return nil }
            // Take first polygon's first ring
            if let polygon = coords.first, let ring = polygon.first {
                return ring.compactMap { coord in
                    guard coord.count >= 2 else { return nil }
                    return CLLocationCoordinate2D(latitude: coord[1], longitude: coord[0])
                }
            }
        }

        return nil
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
    var suggestions: [String] = []

    @State private var showSuggestions = false
    @FocusState private var isFocused: Bool

    var filteredSuggestions: [String] {
        if text.isEmpty {
            return []
        }
        return suggestions
            .filter { $0.localizedCaseInsensitiveContains(text) }
            .sorted()
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(placeholder, text: $text)
                .font(.system(size: 11))
                .textFieldStyle(PlainTextFieldStyle())
                .frame(width: width, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(.systemBackground))
                .cornerRadius(4)
                .focused($isFocused)
                .onChange(of: text) { newValue in
                    showSuggestions = !newValue.isEmpty && !filteredSuggestions.isEmpty
                }
                .onChange(of: isFocused) { focused in
                    if !focused {
                        showSuggestions = false
                    } else if !text.isEmpty {
                        showSuggestions = !filteredSuggestions.isEmpty
                    }
                }

            // Suggestions dropdown
            if showSuggestions && !filteredSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredSuggestions, id: \.self) { suggestion in
                        Button(action: {
                            text = suggestion
                            showSuggestions = false
                            isFocused = false
                        }) {
                            Text(suggestion)
                                .font(.system(size: 11))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.systemBackground))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .hoverEffect()

                        if suggestion != filteredSuggestions.last {
                            Divider()
                        }
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(4)
                .shadow(radius: 4)
                .frame(width: width)
                .zIndex(1000)
            }
        }
    }
}

struct FilterDropdown: View {
    @Binding var selection: String
    let options: [String]
    let width: CGFloat
    var colorMap: [String: Color] = [:]

    func colorForOption(_ option: String) -> Color {
        colorMap[option] ?? .primary
    }

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(action: {
                    selection = option
                }) {
                    HStack {
                        if selection == option {
                            Image(systemName: "checkmark.circle.fill")
                        } else {
                            Image(systemName: "circle")
                                .opacity(0.3)
                        }
                        Text(option)
                            .bold()
                    }
                    .foregroundColor(colorForOption(option))
                }
            }
        } label: {
            HStack {
                Text(selection)
                    .font(.system(size: 11))
                    .bold()
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(colorForOption(selection))
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(.systemBackground))
            .cornerRadius(4)
        }
    }
}

// MARK: - ViewModel

@MainActor
class FieldMapsTableViewModel: ObservableObject {
    @Published var fieldMaps: [TabulaJob] = []
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""

    // Optimized URLSession with connection pooling and compression
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 6
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["Accept-Encoding": "gzip, deflate"]
        return URLSession(configuration: config)
    }()

    // Track pending downloads to avoid duplicates
    private var pendingDownloads = Set<Int>()
    private let downloadQueue = DispatchQueue(label: "com.rotorsync.downloads", attributes: .concurrent)

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

            let (data, _) = try await urlSession.data(from: url)
            let apiResponse = try JSONDecoder().decode(JobsAPIResponse.self, from: data)
            fieldMaps = apiResponse.data.sorted { $0.id > $1.id }
        } catch {
            errorMessage = "Failed to load field maps: \(error.localizedDescription)"
            showError = true
        }
    }

    func refreshData() async {
        // Clear all cached geometry to force fresh downloads
        FieldGeometryCache.shared.clearCache()
        print("🗑️ Cleared all cached geometry")

        // Reload field maps list from server
        await loadTestData()

        // Clear all Tabula fields from the map to force re-import with fresh geometry
        SharedFieldStorage.shared.clearAllFields()
        print("✅ Refresh complete - cleared cache and all fields. Re-select and import fields to get latest geometry")
    }

    func downloadGeometry(for job: TabulaJob) {
        Task {
            print("⬇️ downloadGeometry called for job \(job.id)")

            // Skip if already cached or currently downloading
            if FieldGeometryCache.shared.isCached(fieldId: job.id) {
                print("✅ Job \(job.id) already cached, skipping")
                return
            }

            // Avoid duplicate downloads
            await MainActor.run {
                guard !pendingDownloads.contains(job.id) else {
                    print("⚠️ Job \(job.id) already downloading, skipping")
                    return
                }
                pendingDownloads.insert(job.id)
            }

            defer {
                Task { @MainActor in
                    pendingDownloads.remove(job.id)
                }
            }

            print("📥 Starting download for job \(job.id)...")

            do {
                // Download boundary and spray lines in parallel using TaskGroup
                try await withThrowingTaskGroup(of: (String, Data).self) { group in
                    // Fetch boundary geometry
                    group.addTask {
                        print("📡 Fetching boundary for \(job.id)...")
                        guard let url = URL(string: "http://192.168.68.226:3000/api/field-maps/\(job.id)/geometry?type=requested") else {
                            throw URLError(.badURL)
                        }
                        let (data, response) = try await self.urlSession.data(from: url)
                        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                            print("❌ Boundary fetch failed for \(job.id)")
                            throw URLError(.badServerResponse)
                        }
                        print("✅ Got boundary data for \(job.id)")
                        return ("boundary", data)
                    }

                    // Fetch spray lines
                    group.addTask {
                        print("📡 Fetching spray lines for \(job.id)...")
                        guard let url = URL(string: "http://192.168.68.226:3000/api/field-maps/\(job.id)/geometry?type=worked-detailed") else {
                            throw URLError(.badURL)
                        }
                        let (data, response) = try await self.urlSession.data(from: url)
                        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                            print("⚠️ Spray lines not available for \(job.id)")
                            return ("spray", Data())
                        }
                        print("✅ Got spray lines data for \(job.id)")
                        return ("spray", data)
                    }

                    // Collect results
                    var boundaryData: Data?
                    var sprayData: Data?

                    for try await (type, data) in group {
                        if type == "boundary" {
                            boundaryData = data
                        } else if type == "spray" {
                            sprayData = data
                        }
                    }

                    // Parse and cache
                    guard let boundaryData = boundaryData else {
                        print("❌ No boundary data for \(job.id)")
                        return
                    }

                    print("🔍 Parsing geometry for \(job.id)...")
                    let geometryResponse = try JSONDecoder().decode(GeometryAPIResponse.self, from: boundaryData)
                    let boundaries = geometryResponse.data.features.compactMap { $0.geometry.mapCoordinates }
                    print("✅ Parsed \(boundaries.count) boundaries for \(job.id)")

                    var sprayLines: [[CLLocationCoordinate2D]]? = nil
                    if let sprayData = sprayData, !sprayData.isEmpty {
                        let workedGeometry = try? JSONDecoder().decode(GeometryAPIResponse.self, from: sprayData)
                        sprayLines = workedGeometry?.data.features.compactMap { $0.geometry.mapCoordinates }
                        print("✅ Parsed \(sprayLines?.count ?? 0) spray lines for \(job.id)")
                    }

                    // Cache the geometry
                    print("💾 Caching geometry for \(job.id)...")
                    FieldGeometryCache.shared.cacheGeometry(fieldId: job.id, boundaries: boundaries, sprayLines: sprayLines)
                    print("✅ CACHED job \(job.id)")
                }
            } catch {
                print("❌ ERROR downloading job \(job.id): \(error.localizedDescription)")
            }
        }
    }

    // Batch download for Select All - downloads multiple fields in parallel
    func downloadGeometryBatch(for jobs: [TabulaJob]) {
        Task {
            // Filter out already cached jobs
            let jobsToDownload = jobs.filter { !FieldGeometryCache.shared.isCached(fieldId: $0.id) }

            guard !jobsToDownload.isEmpty else { return }

            print("⬇️ Batch downloading \(jobsToDownload.count) fields...")

            // Download all fields in parallel (URLSession config allows up to 6 concurrent)
            await withTaskGroup(of: Void.self) { group in
                for job in jobsToDownload {
                    group.addTask {
                        await self.downloadSingleField(job)
                    }
                }
            }

            print("✅ Batch download complete - cached \(jobsToDownload.count) fields")
        }
    }

    // Helper for batch downloads - non-isolated version
    private func downloadSingleField(_ job: TabulaJob) async {
        print("📥 downloadSingleField called for job \(job.id)")

        // Skip if currently downloading
        let shouldDownload = await MainActor.run {
            guard !pendingDownloads.contains(job.id) else {
                print("⚠️ Job \(job.id) already downloading")
                return false
            }
            pendingDownloads.insert(job.id)
            return true
        }

        guard shouldDownload else { return }

        defer {
            Task { @MainActor in
                pendingDownloads.remove(job.id)
            }
        }

        print("🚀 Starting download for job \(job.id)")

        do {
            // Download boundary and spray lines in parallel
            try await withThrowingTaskGroup(of: (String, Data).self) { group in
                group.addTask {
                    print("📡 Fetching boundary for \(job.id)...")
                    guard let url = URL(string: "http://192.168.68.226:3000/api/field-maps/\(job.id)/geometry?type=requested") else {
                        throw URLError(.badURL)
                    }
                    let (data, response) = try await self.urlSession.data(from: url)
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        print("❌ Boundary failed for \(job.id)")
                        throw URLError(.badServerResponse)
                    }
                    print("✅ Got boundary for \(job.id)")
                    return ("boundary", data)
                }

                group.addTask {
                    print("📡 Fetching spray for \(job.id)...")
                    guard let url = URL(string: "http://192.168.68.226:3000/api/field-maps/\(job.id)/geometry?type=worked-detailed") else {
                        throw URLError(.badURL)
                    }
                    let (data, response) = try await self.urlSession.data(from: url)
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        print("⚠️ No spray for \(job.id)")
                        return ("spray", Data())
                    }
                    print("✅ Got spray for \(job.id)")
                    return ("spray", data)
                }

                var boundaryData: Data?
                var sprayData: Data?

                for try await (type, data) in group {
                    if type == "boundary" {
                        boundaryData = data
                    } else if type == "spray" {
                        sprayData = data
                    }
                }

                guard let boundaryData = boundaryData else {
                    print("❌ No boundary data for \(job.id)")
                    return
                }

                print("🔍 Parsing \(job.id)...")
                let geometryResponse = try JSONDecoder().decode(GeometryAPIResponse.self, from: boundaryData)
                let boundaries = geometryResponse.data.features.compactMap { $0.geometry.mapCoordinates }
                print("✅ Parsed \(boundaries.count) boundaries for \(job.id)")

                var sprayLines: [[CLLocationCoordinate2D]]? = nil
                if let sprayData = sprayData, !sprayData.isEmpty {
                    let workedGeometry = try? JSONDecoder().decode(GeometryAPIResponse.self, from: sprayData)
                    sprayLines = workedGeometry?.data.features.compactMap { $0.geometry.mapCoordinates }
                }

                print("💾 Caching \(job.id)...")
                FieldGeometryCache.shared.cacheGeometry(fieldId: job.id, boundaries: boundaries, sprayLines: sprayLines)
                print("✅ CACHED \(job.id) successfully")
            }
        } catch {
            print("❌ ERROR downloading \(job.id): \(error.localizedDescription)")
        }
    }

}

// MARK: - Preview

struct FieldMapsTableView_Previews: PreviewProvider {
    static var previews: some View {
        FieldMapsTableView()
    }
}
