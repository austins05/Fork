import CoreData
import CoreLocation
import Foundation

@objc(PinEntity)
public class PinEntity: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var latitude: Double
    @NSManaged public var longitude: Double
    @NSManaged public var iconName: String?
    @NSManaged public var dateCreated: Date?
    @NSManaged public var folder: FolderEntity?
    @NSManaged public var serverPinId: String?
    
    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension PinEntity: Identifiable {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PinEntity> {
        return NSFetchRequest<PinEntity>(entityName: "PinEntity")
    }
}

// MARK: - Conversion to ViewModel
extension PinEntity {
    func toViewModel() -> DroppedPinViewModel {
        DroppedPinViewModel(
            id: self.id ?? UUID(),
            name: self.name ?? "Unknown Pin",
            coordinate: self.coordinate,
            iconName: self.iconName ?? "mappin"
        )
    }
}
