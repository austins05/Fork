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
    let areaNominal: Double?
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
        case areaNominal = "area_nominal"
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        customer = try container.decode(String.self, forKey: .customer)
        area = try container.decode(Double.self, forKey: .area)
        status = try container.decode(String.self, forKey: .status)
        orderNumber = try container.decode(String.self, forKey: .orderNumber)
        requestedUrl = try container.decode(String.self, forKey: .requestedUrl)
        workedUrl = try container.decode(String.self, forKey: .workedUrl)
        modifiedDate = try container.decode(Int.self, forKey: .modifiedDate)
        productList = try container.decode(String.self, forKey: .productList)
        address = try container.decode(String.self, forKey: .address)
        notes = try container.decode(String.self, forKey: .notes)
        deleted = try container.decode(Bool.self, forKey: .deleted)
        rts = try container.decode(Bool.self, forKey: .rts)

        // Decode area_nominal from Tabula API
        areaNominal = try container.decodeIfPresent(Double.self, forKey: .areaNominal)
        print("📊 [DECODE] Job \(id) - area_nominal from API: \(areaNominal ?? -999) hectares")
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
    let coordinate: CLLocationCoordinate2D

    var title: String? {
        fieldMap.name
    }

    var subtitle: String? {
        "\(fieldMap.customer) • \(String(format: "%.2f acres", fieldMap.area))"
    }

    init(fieldMap: FieldMap, coordinate: CLLocationCoordinate2D) {
        self.fieldMap = fieldMap
        self.coordinate = coordinate
        super.init()
    }
}
