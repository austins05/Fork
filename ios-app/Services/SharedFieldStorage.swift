//
//  SharedFieldStorage.swift
//  Rotorsync - Shared storage for field geometries between tabs
//

import Foundation
import Combine
import CoreLocation

class SharedFieldStorage: ObservableObject {
    static let shared = SharedFieldStorage()

    @Published var pendingFieldsToImport: [FieldData] = []
    @Published var shouldImportToMap = false

    private init() {}

    func addFieldsForImport(_ fields: [FieldData]) {
        pendingFieldsToImport = fields
        shouldImportToMap = true
    }

    func clearPendingFields() {
        pendingFieldsToImport = []
        shouldImportToMap = false
    }
}

// FieldData structure for map import
struct FieldData: Identifiable, Codable {
    let id: Int
    let name: String
    let coordinates: [CLLocationCoordinate2D]
    let acres: Double
    let color: String
    let category: String?
    let application: String?
    let description: String?
    let source: FieldSource?

    enum FieldSource: String, Codable {
        case tabula = "tabula"
        case mpz = "mpz"
    }

    init(id: Int, name: String, coordinates: [CLLocationCoordinate2D], acres: Double,
         color: String, category: String?, application: String?, description: String?,
         source: FieldSource? = nil) {
        self.id = id
        self.name = name
        self.coordinates = coordinates
        self.acres = acres
        self.color = color
        self.category = category
        self.application = application
        self.description = description
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case id, name, acres, color, category, application, description, source
        case coordinates
    }

    struct Coordinate: Codable {
        let latitude: Double
        let longitude: Double
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        acres = try c.decode(Double.self, forKey: .acres)
        color = try c.decode(String.self, forKey: .color)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        application = try c.decodeIfPresent(String.self, forKey: .application)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        source = try c.decodeIfPresent(FieldSource.self, forKey: .source)
        let coords = try c.decode([Coordinate].self, forKey: .coordinates)
        coordinates = coords.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(acres, forKey: .acres)
        try c.encode(color, forKey: .color)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(application, forKey: .application)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(source, forKey: .source)
        let coords = coordinates.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
        try c.encode(coords, forKey: .coordinates)
    }
}
