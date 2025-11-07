import Foundation
import CoreLocation

struct FieldData: Identifiable, Codable {
    let id: Int
    let name: String
    let coordinates: [CLLocationCoordinate2D]
    let acres: Double
    let color: String
    let category: String?
    let application: String?
    let description: String?
    let prodDupli: String?
    let productList: String?
    let notes: String?
    let address: String?
    let source: FieldSource? // Track where field came from
    
    // Source tracking for fields
    enum FieldSource: String, Codable {
        case tabula = "tabula"  // From Tabula API
        case mpz = "mpz"        // From MPZ Field Mapper
    }

    init(id: Int, name: String, coordinates: [CLLocationCoordinate2D], acres: Double,
         color: String, category: String?, application: String?, description: String?,
         prodDupli: String? = nil, productList: String? = nil, notes: String? = nil, address: String? = nil,
         source: FieldSource? = nil) {
        self.id = id
        self.name = name
        self.coordinates = coordinates
        self.acres = acres
        self.color = color
        self.category = category
        self.application = application
        self.description = description
        self.prodDupli = prodDupli
        self.productList = productList
        self.notes = notes
        self.address = address
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case id, name, acres, color, category, application, description
        case prodDupli, productList, notes, address, source
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
        prodDupli = try c.decodeIfPresent(String.self, forKey: .prodDupli)
        productList = try c.decodeIfPresent(String.self, forKey: .productList)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        source = try c.decodeIfPresent(FieldSource.self, forKey: .source)
        let coords = try c.decode([Coordinate].self, forKey: .coordinates)
        coordinates = coords.map { CLLocationCoordinate2D(latitude: $0.latitude,
                                                         longitude: $0.longitude) }
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
        try c.encodeIfPresent(prodDupli, forKey: .prodDupli)
        try c.encodeIfPresent(productList, forKey: .productList)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(address, forKey: .address)
        try c.encodeIfPresent(source, forKey: .source)
        let coords = coordinates.map { Coordinate(latitude: $0.latitude,
                                                  longitude: $0.longitude) }
        try c.encode(coords, forKey: .coordinates)
    }
}
