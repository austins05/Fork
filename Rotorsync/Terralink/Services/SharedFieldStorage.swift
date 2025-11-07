//
//  SharedFieldStorage.swift
//  Rotorsync - Shared storage for field geometries between tabs
//

import Foundation
import Combine

// Note: Uses existing FieldData from Features/Map/Models/FieldData.swift

class SharedFieldStorage: ObservableObject {
    static let shared = SharedFieldStorage()

    @Published var pendingFieldsToImport: [FieldData] = []
    @Published var shouldImportToMap = false
    @Published var shouldClearAllFields = false

    private init() {}

    func addFieldsForImport(_ fields: [FieldData]) {
        pendingFieldsToImport = fields
        shouldImportToMap = true
    }

    func clearPendingFields() {
        pendingFieldsToImport = []
        shouldImportToMap = false
    }

    func clearAllFields() {
        pendingFieldsToImport = []
        shouldImportToMap = false
        shouldClearAllFields = true
    }
}
