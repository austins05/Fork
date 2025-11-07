//
//  JobBrowserView.swift
//  Rotorsync - Tabula API Integration
//
//  Enhanced main view for browsing Tabula jobs (field maps)
//

import SwiftUI

struct JobBrowserView: View {
    @StateObject private var viewModel = JobBrowserViewModel()
    @State private var showingFilterSheet = false
    @State private var showingSortSheet = false
    @State private var selectedQuickFilter: QuickFilter = .all
    @State private var sortOption: SortOption = .recentFirst

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                searchBar

                // Quick filter buttons
                quickFilterBar

                // Stats summary
                if !viewModel.jobs.isEmpty {
                    statsSummary
                }

                // Jobs list or empty state
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.filteredJobs.isEmpty && viewModel.jobs.isEmpty {
                    emptyStateView
                } else if viewModel.filteredJobs.isEmpty {
                    noResultsView
                } else {
                    jobsList
                }
            }
            .navigationTitle("Field Jobs")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button(action: { showingSortSheet = true }) {
                            Label("Sort Options", systemImage: "arrow.up.arrow.down")
                        }

                        Divider()

                        Button(action: { selectedQuickFilter = .all }) {
                            Label("Show All", systemImage: "list.bullet")
                        }

                        Button(action: { selectedQuickFilter = .last20 }) {
                            Label("Last 20 Orders", systemImage: "clock")
                        }

                        Button(action: { selectedQuickFilter = .thisMonth }) {
                            Label("This Month", systemImage: "calendar")
                        }

                        Divider()

                        Button(action: { exportJobs() }) {
                            Label("Export Jobs", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { Task { await viewModel.refreshJobs() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .task {
                if viewModel.jobs.isEmpty {
                    await viewModel.loadJobs()
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage)
            }
            .sheet(isPresented: $showingSortSheet) {
                SortOptionsSheet(selectedSort: $sortOption)
            }
            .onChange(of: selectedQuickFilter) { _ in
                applyQuickFilter()
            }
            .onChange(of: sortOption) { _ in
                applySorting()
            }
        }
    }

    // MARK: - View Components

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search jobs, customers, or orders...", text: $viewModel.searchText)
                .textFieldStyle(PlainTextFieldStyle())

            if !viewModel.searchText.isEmpty {
                Button(action: { viewModel.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var quickFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Quick filter buttons
                QuickFilterButton(
                    title: "All Jobs",
                    count: viewModel.jobs.count,
                    icon: "list.bullet",
                    isSelected: selectedQuickFilter == .all
                ) {
                    selectedQuickFilter = .all
                }

                QuickFilterButton(
                    title: "Last 20",
                    count: min(20, viewModel.jobs.count),
                    icon: "clock.fill",
                    isSelected: selectedQuickFilter == .last20
                ) {
                    selectedQuickFilter = .last20
                }

                QuickFilterButton(
                    title: "This Month",
                    count: jobsThisMonth.count,
                    icon: "calendar",
                    isSelected: selectedQuickFilter == .thisMonth
                ) {
                    selectedQuickFilter = .thisMonth
                }

                QuickFilterButton(
                    title: "Overdue",
                    count: overdueJobs.count,
                    icon: "exclamationmark.triangle.fill",
                    isSelected: selectedQuickFilter == .overdue
                ) {
                    selectedQuickFilter = .overdue
                }

                QuickFilterButton(
                    title: "Complete",
                    count: completeJobs.count,
                    icon: "checkmark.circle.fill",
                    isSelected: selectedQuickFilter == .complete
                ) {
                    selectedQuickFilter = .complete
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    private var statsSummary: some View {
        HStack(spacing: 20) {
            StatCard(
                value: "\(viewModel.filteredJobs.count)",
                label: "Jobs",
                icon: "list.bullet",
                color: .blue
            )

            StatCard(
                value: String(format: "%.1f", totalArea),
                label: "Hectares",
                icon: "grid",
                color: .green
            )

            StatCard(
                value: "\(uniqueCustomers.count)",
                label: "Customers",
                icon: "person.2.fill",
                color: .orange
            )

            StatCard(
                value: "\(activeJobs.count)",
                label: "Active",
                icon: "bolt.fill",
                color: .purple
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.systemGray6).opacity(0.5))
    }

    private var jobsList: some View {
        List {
            Section {
                ForEach(sortedAndFilteredJobs) { job in
                    NavigationLink(destination: JobDetailView(job: job, viewModel: viewModel)) {
                        EnhancedJobRow(job: job)
                    }
                }
            } header: {
                HStack {
                    Text("\(sortedAndFilteredJobs.count) job\(sortedAndFilteredJobs.count == 1 ? "" : "s")")
                        .textCase(nil)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(sortOption.displayName)
                        .textCase(nil)
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .refreshable {
            await viewModel.refreshJobs()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Loading jobs...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "map.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Jobs Available")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Pull to refresh or check your backend connection")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: { Task { await viewModel.refreshJobs() } }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
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

    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.gray)

            Text("No Results")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Try adjusting your search or filters")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button(action: {
                viewModel.searchText = ""
                viewModel.filterStatus = "all"
                selectedQuickFilter = .all
            }) {
                Text("Clear All Filters")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Computed Properties

    private var sortedAndFilteredJobs: [TabulaJob] {
        var jobs = viewModel.filteredJobs

        // Apply quick filter
        switch selectedQuickFilter {
        case .all:
            break
        case .last20:
            jobs = Array(jobs.sorted { $0.modifiedDate > $1.modifiedDate }.prefix(20))
        case .thisMonth:
            jobs = jobsThisMonth
        case .overdue:
            jobs = overdueJobs
        case .complete:
            jobs = completeJobs
        }

        // Apply sorting
        switch sortOption {
        case .recentFirst:
            jobs.sort { $0.modifiedDate > $1.modifiedDate }
        case .oldestFirst:
            jobs.sort { $0.modifiedDate < $1.modifiedDate }
        case .areaLargest:
            jobs.sort { $0.area > $1.area }
        case .areaSmallest:
            jobs.sort { $0.area < $1.area }
        case .customerAZ:
            jobs.sort { $0.customer < $1.customer }
        case .statusPriority:
            jobs.sort { statusPriority($0.status) < statusPriority($1.status) }
        }

        return jobs
    }

    private var jobsThisMonth: [TabulaJob] {
        let now = Date()
        let calendar = Calendar.current
        return viewModel.filteredJobs.filter { job in
            let jobDate = Date(timeIntervalSince1970: job.modifiedDate)
            return calendar.isDate(jobDate, equalTo: now, toGranularity: .month)
        }
    }

    private var overdueJobs: [TabulaJob] {
        let now = Date().timeIntervalSince1970
        return viewModel.filteredJobs.filter { job in
            guard let dueDate = job.dueDate else { return false }
            return dueDate < now && job.status.lowercased() != "complete"
        }
    }

    private var completeJobs: [TabulaJob] {
        viewModel.filteredJobs.filter { $0.status.lowercased() == "complete" }
    }

    private var activeJobs: [TabulaJob] {
        viewModel.filteredJobs.filter { $0.status.lowercased() != "complete" }
    }

    private var totalArea: Double {
        sortedAndFilteredJobs.reduce(0) { $0 + $1.area }
    }

    private var uniqueCustomers: Set<String> {
        Set(sortedAndFilteredJobs.map { $0.customer })
    }

    // MARK: - Helper Methods

    private func applyQuickFilter() {
        // Quick filter logic is handled in sortedAndFilteredJobs computed property
    }

    private func applySorting() {
        // Sorting logic is handled in sortedAndFilteredJobs computed property
    }

    private func statusPriority(_ status: String) -> Int {
        switch status.lowercased() {
        case "overdue": return 0
        case "placed": return 1
        case "assigned": return 2
        case "accepted": return 3
        case "complete": return 4
        default: return 5
        }
    }

    private func exportJobs() {
        // Placeholder for export functionality
        print("Export jobs: \(sortedAndFilteredJobs.count) jobs")
    }
}

// MARK: - Quick Filter Enum

enum QuickFilter {
    case all
    case last20
    case thisMonth
    case overdue
    case complete
}

// MARK: - Sort Option Enum

enum SortOption: String, CaseIterable {
    case recentFirst = "Recent First"
    case oldestFirst = "Oldest First"
    case areaLargest = "Area: Largest"
    case areaSmallest = "Area: Smallest"
    case customerAZ = "Customer: A-Z"
    case statusPriority = "Status Priority"

    var displayName: String { rawValue }
    var icon: String {
        switch self {
        case .recentFirst: return "clock.arrow.circlepath"
        case .oldestFirst: return "clock"
        case .areaLargest: return "arrow.down"
        case .areaSmallest: return "arrow.up"
        case .customerAZ: return "textformat"
        case .statusPriority: return "flag.fill"
        }
    }
}

// MARK: - Quick Filter Button

struct QuickFilterButton: View {
    let title: String
    let count: Int
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .fontWeight(isSelected ? .semibold : .regular)

                    Text("\(count)")
                        .font(.caption2)
                        .foregroundColor(isSelected ? .white : .secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(10)
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)

            Text(value)
                .font(.headline)
                .fontWeight(.bold)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(10)
    }
}

// MARK: - Enhanced Job Row

struct EnhancedJobRow: View {
    let job: TabulaJob

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(statusColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 8) {
                // Job name and status
                HStack {
                    Text(job.name)
                        .font(.headline)

                    Spacer()

                    StatusBadge(status: job.status)
                }

                // Customer
                if !job.customer.isEmpty {
                    Label(job.customer, systemImage: "person.fill")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Bottom row: Area, Order #, Date
                HStack(spacing: 16) {
                    Label(job.areaFormatted, systemImage: "grid")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !job.orderNumber.isEmpty {
                        Label("#\(job.orderNumber)", systemImage: "number")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(relativeDate(from: job.modifiedDate))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch job.status.lowercased() {
        case "complete": return .green
        case "placed": return .blue
        case "assigned": return .orange
        case "accepted": return .yellow
        default: return .gray
        }
    }

    private func relativeDate(from timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Sort Options Sheet

struct SortOptionsSheet: View {
    @Binding var selectedSort: SortOption
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button(action: {
                        selectedSort = option
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: option.icon)
                                .foregroundColor(.blue)
                                .frame(width: 30)

                            Text(option.displayName)
                                .foregroundColor(.primary)

                            Spacer()

                            if selectedSort == option {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sort By")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Status Badge (reused from original)

struct StatusBadge: View {
    let status: String

    private var backgroundColor: Color {
        switch status.lowercased() {
        case "complete": return .green
        case "placed": return .blue
        case "assigned": return .orange
        case "accepted": return .yellow
        default: return .gray
        }
    }

    var body: some View {
        Text(status.capitalized)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor.opacity(0.2))
            .foregroundColor(backgroundColor)
            .cornerRadius(6)
    }
}

// MARK: - Preview

struct JobBrowserView_Previews: PreviewProvider {
    static var previews: some View {
        JobBrowserView()
    }
}
