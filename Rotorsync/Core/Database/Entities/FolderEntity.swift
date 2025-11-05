import CoreData
import Foundation

@objc(FolderEntity)
public class FolderEntity: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var pins: NSSet?
    @NSManaged public var fields: NSSet?
    
    public var pinsArray: [PinEntity] {
        guard let pinsSet = pins else { return [] }
        return (pinsSet.allObjects as? [PinEntity] ?? [])
            .sorted { ($0.dateCreated ?? Date()) > ($1.dateCreated ?? Date()) }
    }
    
    public var fieldsArray: [FieldEntity] {
        guard let fieldsSet = fields else { return [] }
        return (fieldsSet.allObjects as? [FieldEntity] ?? [])
            .sorted { ($0.dateImported ?? Date()) > ($1.dateImported ?? Date()) }
    }
    
    public var allItemsCount: Int {
        let pinsCount = pins?.count ?? 0
        let fieldsCount = fields?.count ?? 0
        return pinsCount + fieldsCount
    }
}

extension FolderEntity: Identifiable {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<FolderEntity> {
        return NSFetchRequest<FolderEntity>(entityName: "FolderEntity")
    }
}
