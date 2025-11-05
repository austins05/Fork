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

// MARK: - Field Map Model

struct FieldMap: Identifiable, Codable {
    let id: String
    let customerId: String
    let name: String
    let description: String?
    let area: Double? // in hectares or acres
    let boundaries: [Coordinate]
    let center: Coordinate?
    let metadata: FieldMapMetadata?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case customerId = "customer_id"
        case name
        case description
        case area
        case boundaries
        case center
        case metadata
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Coordinate

struct Coordinate: Codable, Hashable {
    let latitude: Double
    let longitude: Double

    enum CodingKeys: String, CodingKey {
        case latitude = "lat"
        case longitude = "lon"
    }

    // Convert to CLLocationCoordinate2D for MapKit
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Field Map Metadata

struct FieldMapMetadata: Codable {
    let cropType: String?
    let season: String?
    let lastActivity: Date?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case cropType = "crop_type"
        case season
        case lastActivity = "last_activity"
        case notes
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
        fieldMap.center?.clCoordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    var title: String? {
        fieldMap.name
    }

    var subtitle: String? {
        if let area = fieldMap.area {
            return String(format: "%.2f acres", area)
        }
        return nil
    }

    init(fieldMap: FieldMap) {
        self.fieldMap = fieldMap
    }
}

// MARK: - Map Overlay

class FieldMapOverlay: NSObject, MKOverlay {
    let fieldMap: FieldMap
    let coordinates: [CLLocationCoordinate2D]
    let boundingMapRect: MKMapRect

    var coordinate: CLLocationCoordinate2D {
        boundingMapRect.origin.coordinate
    }

    init(fieldMap: FieldMap) {
        self.fieldMap = fieldMap
        self.coordinates = fieldMap.boundaries.map { $0.clCoordinate }

        // Calculate bounding rect
        var rect = MKMapRect.null
        for coord in coordinates {
            let point = MKMapPoint(coord)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
            rect = rect.union(pointRect)
        }
        self.boundingMapRect = rect

        super.init()
    }
}

// MARK: - Helper Extensions

extension MKMapRect {
    var coordinate: CLLocationCoordinate2D {
        let center = MKMapPoint(x: midX, y: midY)
        return center.coordinate
    }
}
