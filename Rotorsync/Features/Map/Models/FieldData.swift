import Foundation
import CoreLocation

struct FieldData: Identifiable, Codable {
    let id: Int
    let jobId: Int?  // Original job/order ID (for Tabula fields)
    let name: String
    let coordinates: [CLLocationCoordinate2D]
    let workedCoordinates: [[CLLocationCoordinate2D]]? // Multiple spray line polygons
    let acres: Double  // Requested acres
    let nominalAcres: Double?  // Nominal/flown acres (gross coverage area)
    let color: String  // Fill color
    let boundaryColor: String?  // Stroke/outline color (optional)
    let contractorDashColor: String?  // Dashed border color for contractor (optional)
    let category: String?
    let application: String?
    let description: String?
    let prodDupli: String?
    let productList: String?
    let notes: String?
    let address: String?
    let source: FieldSource? // Track where field came from
    let crop: String?
    
    // Source tracking for fields
    enum FieldSource: String, Codable {
        case tabula = "tabula"  // From Tabula API
        case mpz = "mpz"        // From MPZ Field Mapper
    }

    init(id: Int, jobId: Int? = nil, name: String, coordinates: [CLLocationCoordinate2D], acres: Double,
         color: String, boundaryColor: String? = nil, contractorDashColor: String? = nil,
         category: String?, application: String?, description: String?,
         prodDupli: String? = nil, productList: String? = nil, notes: String? = nil, address: String? = nil,
         source: FieldSource? = nil, crop: String? = nil, nominalAcres: Double? = nil, workedCoordinates: [[CLLocationCoordinate2D]]? = nil) {
        self.id = id
        self.jobId = jobId
        self.name = name
        self.coordinates = coordinates
        self.workedCoordinates = workedCoordinates
        self.acres = acres
        self.nominalAcres = nominalAcres
        self.color = color
        self.boundaryColor = boundaryColor
        self.contractorDashColor = contractorDashColor
        self.category = category
        self.application = application
        self.description = description
        self.prodDupli = prodDupli
        self.productList = productList
        self.notes = notes
        self.address = address
        self.source = source
        self.crop = crop
    }

    enum CodingKeys: String, CodingKey {
        case id, jobId, name, acres, nominalAcres, color, boundaryColor, contractorDashColor, category, application, description
        case prodDupli, productList, notes, address, source, crop
        case coordinates, workedCoordinates
    }

    struct Coordinate: Codable {
        let latitude: Double
        let longitude: Double
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        jobId = try c.decodeIfPresent(Int.self, forKey: .jobId)
        name = try c.decode(String.self, forKey: .name)
        acres = try c.decode(Double.self, forKey: .acres)
        nominalAcres = try c.decodeIfPresent(Double.self, forKey: .nominalAcres)
        color = try c.decode(String.self, forKey: .color)
        boundaryColor = try c.decodeIfPresent(String.self, forKey: .boundaryColor)
        contractorDashColor = try c.decodeIfPresent(String.self, forKey: .contractorDashColor)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        application = try c.decodeIfPresent(String.self, forKey: .application)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        prodDupli = try c.decodeIfPresent(String.self, forKey: .prodDupli)
        productList = try c.decodeIfPresent(String.self, forKey: .productList)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        source = try c.decodeIfPresent(FieldSource.self, forKey: .source)
        crop = try c.decodeIfPresent(String.self, forKey: .crop)
        let coords = try c.decode([Coordinate].self, forKey: .coordinates)
        coordinates = coords.map { CLLocationCoordinate2D(latitude: $0.latitude,
                                                         longitude: $0.longitude) }
        if let workedPolygons = try c.decodeIfPresent([[Coordinate]].self, forKey: .workedCoordinates) {
            workedCoordinates = workedPolygons.map { polygon in
                polygon.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            }
        } else {
            workedCoordinates = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(jobId, forKey: .jobId)
        try c.encode(name, forKey: .name)
        try c.encode(acres, forKey: .acres)
        try c.encodeIfPresent(nominalAcres, forKey: .nominalAcres)
        try c.encode(color, forKey: .color)
        try c.encodeIfPresent(boundaryColor, forKey: .boundaryColor)
        try c.encodeIfPresent(contractorDashColor, forKey: .contractorDashColor)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(application, forKey: .application)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(prodDupli, forKey: .prodDupli)
        try c.encodeIfPresent(productList, forKey: .productList)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(address, forKey: .address)
        try c.encodeIfPresent(source, forKey: .source)
        try c.encodeIfPresent(crop, forKey: .crop)
        let coords = coordinates.map { Coordinate(latitude: $0.latitude,
                                                  longitude: $0.longitude) }
        try c.encode(coords, forKey: .coordinates)
        if let workedPolygons = workedCoordinates {
            let workedPolygonsMapped = workedPolygons.map { polygon in
                polygon.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
            }
            try c.encode(workedPolygonsMapped, forKey: .workedCoordinates)
        }
    }
}
