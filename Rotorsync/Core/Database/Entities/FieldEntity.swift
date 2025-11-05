import CoreData
import CoreLocation
import Foundation

@objc(FieldEntity)
public class FieldEntity: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var coordinatesData: Data?
    @NSManaged public var acres: Double
    @NSManaged public var color: String?
    @NSManaged public var category: String?
    @NSManaged public var application: String?
    @NSManaged public var fieldDescription: String?
    @NSManaged public var dateImported: Date?
    @NSManaged public var folder: FolderEntity?
    
    public var coordinates: [[String: Double]] {
        get {
            guard let data = coordinatesData else { return [] }
            return (try? JSONDecoder().decode([[String: Double]].self, from: data)) ?? []
        }
        set {
            coordinatesData = try? JSONEncoder().encode(newValue)
        }
    }
    
    public var clCoordinates: [CLLocationCoordinate2D] {
        coordinates.compactMap { dict in
            guard let lat = dict["lat"], let lng = dict["lng"] else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
    }
}

extension FieldEntity: Identifiable {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<FieldEntity> {
        return NSFetchRequest<FieldEntity>(entityName: "FieldEntity")
    }
}
