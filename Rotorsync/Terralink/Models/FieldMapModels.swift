//
//  FieldMapModels.swift
//  Rotorsync - Terralink Integration
//
//  Models for Tabula API field maps and customers
//

import Foundation
import MapKit

// MARK: - Customer Model

struct Customer: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let email: String?
    let phone: String?
    let address: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case email
        case phone
        case address
        case createdAt = "created_at"
    }
}

// MARK: - Field Map Model (Tabula Job)

struct FieldMap: Identifiable, Codable {
    let id: Int
    let name: String
    let customer: String
    let area: Double
    let status: String
    let orderNumber: String
    let requestedUrl: String
    let workedUrl: String
    let modifiedDate: Int
    let productList: String
    let address: String
    let notes: String
    let deleted: Bool
    let rts: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case customer
        case area
        case status
        case orderNumber
        case requestedUrl
        case workedUrl
        case modifiedDate
        case productList
        case address
        case notes
        case deleted
        case rts
    }
}

// MARK: - API Response Models

struct APIResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let error: String?
    let count: Int?
}

struct CustomerSearchResponse: Codable {
    let success: Bool
    let count: Int
    let data: [Customer]
}

struct FieldMapsResponse: Codable {
    let success: Bool
    let count: Int
    let customersProcessed: Int?
    let data: [FieldMap]

    enum CodingKeys: String, CodingKey {
        case success
        case count
        case customersProcessed = "customers_processed"
        case data
    }
}

// MARK: - Map Annotations

class FieldMapAnnotation: NSObject, MKAnnotation {
    let fieldMap: FieldMap

    var coordinate: CLLocationCoordinate2D {
        // We'll get this from geometry data
        CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    var title: String? {
        fieldMap.name
    }

    var subtitle: String? {
        String(format: "%.2f acres", fieldMap.area)
    }

    init(fieldMap: FieldMap) {
        self.fieldMap = fieldMap
    }
}
