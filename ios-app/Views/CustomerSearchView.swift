//
//  CustomerSearchView.swift
//  Rotorsync - Terralink Integration
//
//  Customer search with multi-select functionality
//

import SwiftUI

struct CustomerSearchView: View {
    @ObservedObject var viewModel: FieldMapsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""
    @State private var searchResults: [Customer] = []
    @State private var isSearching = false
    @State private var localSelectedCustomers: Set<Customer> = []

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                searchBar

                // Results count and clear button
                if !searchResults.isEmpty || !localSelectedCustomers.isEmpty {
                    resultsSummary
                }

                // Search results list
                if isSearching {
                    loadingView
                } else if searchResults.isEmpty && searchQuery.isEmpty {
                    emptySearchView
                } else if searchResults.isEmpty {
                    noResultsView
                } else {
                    resultsList
                }
            }
            .navigationTitle("Search Customers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add (\(localSelectedCustomers.count))") {
                        viewModel.addCustomers(Array(localSelectedCustomers))
                        dismiss()
                    }
                    .disabled(localSelectedCustomers.isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                // Pre-select customers that are already in the view model
                localSelectedCustomers = Set(viewModel.selectedCustomers)
            }
        }
    }

    // MARK: - View Components

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("Search by customer name...", text: $searchQuery)
                .textFieldStyle(PlainTextFieldStyle())
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: searchQuery) { newValue in
                    // Debounce search
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                        if searchQuery == newValue && !newValue.isEmpty {
                            await performSearch()
                        } else if newValue.isEmpty {
                            searchResults = []
                        }
                    }
                }

            if !searchQuery.isEmpty {
                Button(action: {
                    searchQuery = ""
                    searchResults = []
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding()
    }

    private var resultsSummary: some View {
        HStack {
            if !searchResults.isEmpty {
                Text("\(searchResults.count) results")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !localSelectedCustomers.isEmpty {
                Button(action: {
                    localSelectedCustomers.removeAll()
                }) {
                    Text("Clear Selection")
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private var resultsList: some View {
        List {
            ForEach(searchResults) { customer in
                CustomerSearchRow(
                    customer: customer,
                    isSelected: localSelectedCustomers.contains(customer)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleCustomerSelection(customer)
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Searching...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptySearchView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.gray)

            Text("Search for Customers")
                .font(.headline)

            Text("Enter a customer name to search")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.gray)

            Text("No Results")
                .font(.headline)

            Text("No customers found for '\(searchQuery)'")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Methods

    private func performSearch() async {
        guard !searchQuery.isEmpty else { return }

        isSearching = true
        defer { isSearching = false }

        do {
            let results = try await viewModel.apiService.searchCustomers(query: searchQuery)
            await MainActor.run {
                searchResults = results
            }
        } catch {
            print("Search error: \(error.localizedDescription)")
            await MainActor.run {
                searchResults = []
            }
        }
    }

    private func toggleCustomerSelection(_ customer: Customer) {
        if localSelectedCustomers.contains(customer) {
            localSelectedCustomers.remove(customer)
        } else {
            localSelectedCustomers.insert(customer)
        }
    }
}

// MARK: - Customer Search Row

struct CustomerSearchRow: View {
    let customer: Customer
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(customer.name)
                    .font(.headline)

                if let email = customer.email {
                    Text(email)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if let address = customer.address {
                    Text(address)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title3)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.gray)
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

struct CustomerSearchView_Previews: PreviewProvider {
    static var previews: some View {
        CustomerSearchView(viewModel: FieldMapsViewModel())
    }
}
