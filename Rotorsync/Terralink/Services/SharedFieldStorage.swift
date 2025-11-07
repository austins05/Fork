//
//  SharedFieldStorage.swift
//  Rotorsync - Shared storage for imported fields
//

import Foundation
import Combine

/// Shared singleton for managing imported fields across tabs
class SharedFieldStorage: ObservableObject {
    static let shared = SharedFieldStorage()

    @Published var importedFields: [FieldData] = []

    private init() {
        // Load from UserDefaults if needed
        loadFields()
    }

    func addField(_ field: FieldData) {
        print("📦 SharedFieldStorage.addField called for: \(field.name) (ID: \(field.id), Source: \(field.source?.rawValue ?? "nil"))")
        print("   Current fields count: \(importedFields.count)")

        if !importedFields.contains(where: { $0.id == field.id }) {
            importedFields.append(field)
            saveFields()
            print("   ✅ Field added! New count: \(importedFields.count)")
            print("   📝 All field IDs now: \(importedFields.map { $0.id })")
        } else {
            print("   ⚠️  Field already exists, skipping (ID: \(field.id))")
        }
    }

    func removeField(_ field: FieldData) {
        importedFields.removeAll { $0.id == field.id }
        saveFields()
    }

    func clearAllFields() {
        print("🗑️  Clearing all imported fields")
        importedFields.removeAll()
        saveFields()
    }

    // FIXED: Clear Tabula-sourced fields AND fields with nil source (legacy fields)
    func clearTabulaFields() {
        print("🗑️  Clearing Tabula-sourced fields")
        let beforeCount = importedFields.count
        
        // Count fields by source before clearing
        let tabulaCount = importedFields.filter { $0.source == .tabula }.count
        let nilSourceCount = importedFields.filter { $0.source == nil }.count
        let mpzCount = importedFields.filter { $0.source == .mpz }.count
        
        print("   📊 Before clear: \(tabulaCount) tabula, \(nilSourceCount) nil source, \(mpzCount) mpz")
        
        // Remove both .tabula AND nil source (nil = legacy Tabula fields from before source tracking)
        importedFields.removeAll { $0.source == .tabula || $0.source == nil }
        
        let afterCount = importedFields.count
        let removed = beforeCount - afterCount
        print("   ✅ Removed \(removed) Tabula fields (including legacy), \(afterCount) fields remaining")
        saveFields()
    }

    // Get count of fields by source
    func fieldCount(for source: FieldData.FieldSource) -> Int {
        return importedFields.filter { $0.source == source }.count
    }

    private func saveFields() {
        if let encoded = try? JSONEncoder().encode(importedFields) {
            UserDefaults.standard.set(encoded, forKey: "importedFields")
        }
    }

    private func loadFields() {
        if let data = UserDefaults.standard.data(forKey: "importedFields"),
           let decoded = try? JSONDecoder().decode([FieldData].self, from: data) {
            // Filter out fields with bad coordinate data (< 3 coords can't render polygon)
            let validFields = decoded.filter { $0.coordinates.count >= 3 }
            let badFields = decoded.filter { $0.coordinates.count < 3 }
            
            if !badFields.isEmpty {
                print("🗑️ MIGRATION: Removing \(badFields.count) fields with insufficient coordinates:")
                for field in badFields {
                    print("   - Removed: \(field.name) (ID: \(field.id)) - only had \(field.coordinates.count) coords")
                }
            }
            
            importedFields = validFields
            print("🔄 Loaded \(importedFields.count) valid fields from UserDefaults:")
            for field in importedFields {
                print("   - ID: \(field.id), Name: \(field.name), Coords: \(field.coordinates.count), Source: \(field.source?.rawValue ?? "nil (legacy)")")
            }
            
            // Migration: Fields with nil source are assumed to be legacy Tabula imports
            // They will be cleared when clearTabulaFields() is called
            let legacyCount = importedFields.filter { $0.source == nil }.count
            if legacyCount > 0 {
                print("⚠️  WARNING: Found \(legacyCount) legacy fields without source tracking")
                print("   These will be treated as Tabula fields and removed when 'Clear' is clicked")
            }
            
            // Save cleaned data back
            if !badFields.isEmpty {
                saveFields()
            }
        } else {
            print("🔄 No fields found in UserDefaults, starting fresh")
        }
    }
}
