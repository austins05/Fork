//
//  TabulaJobModels.swift
//  Rotorsync - Tabula API Integration
//
//  Models for Tabula API jobs (field maps) and geometry
//

import Foundation
import MapKit

// MARK: - Job (Field Map) Model

struct TabulaJob: Identifiable, Codable {
    let id: Int
    let name: String
    let customer: String
    let area: Double
    let status: String
    let orderNumber: String
    let requestedUrl: String?
    let workedUrl: String?
    let modifiedDate: TimeInterval
    let dueDate: TimeInterval?
    let productList: String
    let address: String
    let notes: String
    let deleted: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, customer, area, status
        case orderNumber, requestedUrl, workedUrl
        case modifiedDate, dueDate, productList
        case address, notes, deleted
    }

    // Computed properties
    var modifiedDateFormatted: String {
        let date = Date(timeIntervalSince1970: modifiedDate)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var dueDateFormatted: String? {
        guard let dueDate = dueDate else { return nil }
        let date = Date(timeIntervalSince1970: dueDate)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    var statusColor: String {
        switch status.lowercased() {
        case "complete": return "green"
        case "placed": return "blue"
        case "assigned": return "orange"
        case "accepted": return "yellow"
        default: return "gray"
        }
    }

    var areaFormatted: String {
        String(format: "%.2f ha", area)
    }
}

// MARK: - Job Detail Model

struct TabulaJobDetail: Identifiable, Codable {
    let id: Int
    let name: String
    let customer: String
    let customerFullName: String?
    let area: Double
    let status: String
    let orderNumber: String
    let orderName: String
    let blockName: String
    let orderType: String
    let subtype: String
    let address: String
    let notes: String
    let comments: String
    let dueDate: TimeInterval?
    let modifiedDate: TimeInterval
    let creationDate: TimeInterval
    let productList: String
    let productRates: [ProductRate]?
    let requestedUrl: String?
    let workedUrl: String?
    let deleted: Bool
    let color: String
    let urgency: String

    enum CodingKeys: String, CodingKey {
        case id, name, customer, customerFullName, area, status
        case orderNumber, orderName, blockName, orderType, subtype
        case address, notes, comments, dueDate, modifiedDate, creationDate
        case productList, productRates, requestedUrl, workedUrl
        case deleted, color, urgency
    }
}

// MARK: - Product Rate

struct ProductRate: Codable {
    let applicationRate: ApplicationRate?
    let product: Product?
    let quantity: Double?

    enum CodingKeys: String, CodingKey {
        case applicationRate = "application_rate"
        case product, quantity
    }
}

struct ApplicationRate: Codable {
    let rate: Double
    let unit: String
}

struct Product: Codable {
    let id: Int
    let name: String
    let units: String?
    let areaUnit: String?
    let weightUnit: String?

    enum CodingKeys: String, CodingKey {
        case id, name, units
        case areaUnit = "area_unit"
        case weightUnit = "weight_unit"
    }
}

// MARK: - GeoJSON Models

struct GeoJSONFeatureCollection: Codable {
    let type: String
    let features: [GeoJSONFeature]
}

struct GeoJSONFeature: Codable {
    let type: String
    let geometry: GeoJSONGeometry
    let properties: GeoJSONProperties?
}

struct GeoJSONGeometry: Codable {
    let type: String
    let coordinates: [[[Double]]]  // For Polygon: [[[lon, lat], [lon, lat], ...]]
}

struct GeoJSONProperties: Codable {
    let name: String?
    let colour: String?
    let showLabel: Bool?
    let showArea: Bool?
    let component: String?
    let templateType: String?

    enum CodingKeys: String, CodingKey {
        case name, colour, component
        case showLabel = "show_label"
        case showArea = "show_area"
        case templateType = "template_type"
    }
}

// MARK: - Helper: Convert GeoJSON to MapKit coordinates

extension GeoJSONGeometry {
    /// Convert GeoJSON coordinates to CLLocationCoordinate2D array
    /// GeoJSON format: [[[longitude, latitude], ...]]
    var mapCoordinates: [CLLocationCoordinate2D] {
        guard type == "Polygon", !coordinates.isEmpty else { return [] }

        // Get the first ring (outer boundary)
        let outerRing = coordinates[0]

        return outerRing.map { coord in
            // GeoJSON is [longitude, latitude]
            guard coord.count >= 2 else {
                return CLLocationCoordinate2D(latitude: 0, longitude: 0)
            }
            return CLLocationCoordinate2D(latitude: coord[1], longitude: coord[0])
        }
    }

    /// Calculate center point of polygon
    var centerCoordinate: CLLocationCoordinate2D {
        let coords = mapCoordinates
        guard !coords.isEmpty else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }

        let sumLat = coords.reduce(0.0) { $0 + $1.latitude }
        let sumLon = coords.reduce(0.0) { $0 + $1.longitude }

        return CLLocationCoordinate2D(
            latitude: sumLat / Double(coords.count),
            longitude: sumLon / Double(coords.count)
        )
    }
}

// MARK: - API Response Models

struct JobsAPIResponse: Codable {
    let success: Bool
    let count: Int?
    let data: [TabulaJob]
}

struct JobDetailAPIResponse: Codable {
    let success: Bool
    let data: TabulaJobDetail
}

struct GeometryAPIResponse: Codable {
    let success: Bool
    let format: String
    let data: GeoJSONFeatureCollection
}

// MARK: - Map Overlay

class JobMapOverlay: NSObject, MKOverlay {
    let job: TabulaJob
    let coordinates: [CLLocationCoordinate2D]
    let boundingMapRect: MKMapRect

    var coordinate: CLLocationCoordinate2D {
        // Return center of bounding rect
        let center = MKMapPoint(x: boundingMapRect.midX, y: boundingMapRect.midY)
        return center.coordinate
    }

    init(job: TabulaJob, coordinates: [CLLocationCoordinate2D]) {
        self.job = job
        self.coordinates = coordinates

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

// MARK: - Map Annotation

class JobAnnotation: NSObject, MKAnnotation {
    let job: TabulaJob
    let coordinate: CLLocationCoordinate2D

    var title: String? {
        job.name
    }

    var subtitle: String? {
        "\(job.customer) • \(job.areaFormatted)"
    }

    init(job: TabulaJob, coordinate: CLLocationCoordinate2D) {
        self.job = job
        self.coordinate = coordinate
        super.init()
    }
}
