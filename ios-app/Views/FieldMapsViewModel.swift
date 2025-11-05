//
//  FieldMapsViewModel.swift
//  Rotorsync - Terralink Integration
//
//  ViewModel for managing field maps and customer selection
//

import Foundation
import SwiftUI
import Combine

@MainActor
class FieldMapsViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var selectedCustomers: [Customer] = []
    @Published var fieldMaps: [FieldMap] = []
    @Published var selectedFieldMap: FieldMap?
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""

    // MARK: - Services

    let apiService = TabulaAPIService()

    // MARK: - Methods

    /// Add customers to selection
    func addCustomers(_ customers: [Customer]) {
        for customer in customers {
            if !selectedCustomers.contains(where: { $0.id == customer.id }) {
                selectedCustomers.append(customer)
            }
        }
    }

    /// Remove customer from selection
    func removeCustomer(_ customer: Customer) {
        selectedCustomers.removeAll { $0.id == customer.id }
    }

    /// Clear all selected customers
    func clearSelection() {
        selectedCustomers.removeAll()
    }

    /// Import field maps for all selected customers
    func importFieldMaps() async {
        guard !selectedCustomers.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let customerIds = selectedCustomers.map { $0.id }
            let maps = try await apiService.getFieldMapsForCustomers(customerIds: customerIds)

            // Merge with existing field maps (avoid duplicates)
            for map in maps {
                if !fieldMaps.contains(where: { $0.id == map.id }) {
                    fieldMaps.append(map)
                }
            }

            // Sort by name
            fieldMaps.sort { $0.name < $1.name }

            print("✅ Imported \(maps.count) field maps")

        } catch {
            errorMessage = error.localizedDescription
            showError = true
            print("❌ Error importing field maps: \(error.localizedDescription)")
        }
    }

    /// Refresh field maps for all imported maps
    func refreshFieldMaps() async {
        guard !fieldMaps.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        // Get unique customer IDs from current field maps
        let customerIds = Array(Set(fieldMaps.map { $0.customerId }))

        do {
            let maps = try await apiService.getFieldMapsForCustomers(customerIds: customerIds)
            fieldMaps = maps.sorted { $0.name < $1.name }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// Remove a field map
    func removeFieldMap(_ fieldMap: FieldMap) {
        fieldMaps.removeAll { $0.id == fieldMap.id }
    }

    /// Clear all field maps
    func clearAllFieldMaps() {
        fieldMaps.removeAll()
    }

    /// Get field maps for a specific customer
    func getFieldMaps(for customer: Customer) -> [FieldMap] {
        return fieldMaps.filter { $0.customerId == customer.id }
    }

    /// Check backend health
    func checkBackendHealth() async -> Bool {
        do {
            return try await apiService.checkHealth()
        } catch {
            print("Backend health check failed: \(error.localizedDescription)")
            return false
        }
    }
}
