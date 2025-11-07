//
//  FieldMapsViewModel.swift
//  Rotorsync - Terralink Integration
//
//  ViewModel for managing field maps and customer selection
//

import Foundation
import SwiftUI
import Combine
import CoreLocation

@MainActor
class FieldMapsViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var selectedCustomers: [Customer] = []
    @Published var fieldMaps: [FieldMap] = []
    @Published var selectedFieldMap: FieldMap?
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var hideMapGeometries = false
    @Published var hasAutoLoaded = false  // NEW: Track if we've auto-loaded

    // MARK: - Services

    let apiService = TabulaAPIService()
    private let fieldStorage = SharedFieldStorage.shared

    // MARK: - Methods

    /// Auto-load recent field maps on first view appearance
    func autoLoadRecentFieldMaps() async {
        // Only auto-load once per app session
        guard !hasAutoLoaded else {
            print("📱 Skipping auto-load (already loaded)")
            return
        }
        
        hasAutoLoaded = true
        isLoading = true
        defer { isLoading = false }

        do {
            print("📱 Auto-loading recent field maps...")
            let maps = try await apiService.getRecentFieldMaps(limit: 20)
            
            // Add to field maps list
            fieldMaps = maps.sorted { $0.name < $1.name }
            
            // Fetch geometries and add to Map tab
            await addFieldsToMapTab(maps)
            
            print("✅ Auto-loaded \(maps.count) field maps")
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            print("❌ Auto-load failed: \(error.localizedDescription)")
        }
    }

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

            // Fetch geometries and add to SharedFieldStorage for Map tab display
            await addFieldsToMapTab(maps)

            // Show geometries on map for newly imported fields
            hideMapGeometries = false

            print("✅ Imported \(maps.count) field maps")

        } catch {
            errorMessage = error.localizedDescription
            showError = true
            print("❌ Error importing field maps: \(error.localizedDescription)")
        }
    }

    // Fetch geometries and add to SharedFieldStorage
    private func addFieldsToMapTab(_ maps: [FieldMap]) async {
        print("🗺️  Adding \(maps.count) fields to Map tab...")
        
        var successCount = 0
        var failCount = 0
        
        for map in maps {
            do {
                // Fetch geometry from Tabula API
                let geometryJSON = try await apiService.getFieldGeometry(fieldId: "\(map.id)", type: "requested")
                
                // Extract coordinates from GeoJSON
                if let coordinates = extractCoordinates(from: geometryJSON) {
                    // Convert FieldMap to FieldData
                    let fieldData = FieldData(
                        id: map.id,
                        name: map.name,
                        coordinates: coordinates,
                        acres: map.area,
                        color: "#4A90E2",  // Default blue color
                        category: map.productList,
                        application: map.productList,
                        description: map.notes ?? map.customer,
                        source: .tabula  // Mark as Tabula source
                    )
                    
                    // Add to SharedFieldStorage
                    fieldStorage.addField(fieldData)
                    successCount += 1
                    print("   ✅ Added '\(map.name)' to Map tab (\(coordinates.count) coordinates)")
                } else {
                    failCount += 1
                    print("   ⚠️  No geometry found for '\(map.name)'")
                }
                
            } catch {
                failCount += 1
                print("   ❌ Failed to fetch geometry for '\(map.name)': \(error.localizedDescription)")
            }
        }
        
        print("🗺️  Map tab update complete: \(successCount) added, \(failCount) failed")
    }

    // Extract coordinates from GeoJSON response
    private func extractCoordinates(from geoJSON: [String: Any]) -> [CLLocationCoordinate2D]? {
        guard let data = geoJSON["data"] as? [String: Any],
              let features = data["features"] as? [[String: Any]],
              let firstFeature = features.first,
              let geometry = firstFeature["geometry"] as? [String: Any],
              let type = geometry["type"] as? String,
              let coordinates = geometry["coordinates"] as? [[[Double]]] else {
            print("   ❌ Failed to extract coordinates from GeoJSON structure")
            return nil
        }

        // Handle Polygon type (first array of coordinates)
        guard type == "Polygon", let ring = coordinates.first else {
            print("   ❌ Not a Polygon type or empty coordinates")
            return nil
        }

        // Convert [[lon, lat]] to CLLocationCoordinate2D
        let coords = ring.compactMap { coord -> CLLocationCoordinate2D? in
            guard coord.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: coord[1], longitude: coord[0])
        }
        
        return coords.count >= 3 ? coords : nil  // Need at least 3 coords for polygon
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
            
            // Update Map tab fields too
            await addFieldsToMapTab(maps)
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

    /// Clear map geometries (removes all Tabula field boundaries from Map tab)
    func clearMapGeometries() {
        print("🗑️  Clearing Tabula field geometries from Map tab...")
        // Clear Tabula fields from SharedFieldStorage (affects Map tab)
        fieldStorage.clearTabulaFields()
        print("   ✅ Map geometries cleared")
    }

    /// Show map geometries again
    func showMapGeometries() {
        hideMapGeometries = false
    }

    /// Computed property for map field maps (respects hide flag)
    var mapFieldMaps: [FieldMap] {
        return hideMapGeometries ? [] : fieldMaps
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
