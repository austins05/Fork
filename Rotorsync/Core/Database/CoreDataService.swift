import CoreData
import Foundation

class CoreDataService {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
    }
    
    // MARK: - Folder Operations
    
    @MainActor
    func createFolder(name: String) async throws -> FolderEntity {
        let folder = FolderEntity(context: context)
        folder.id = UUID()
        folder.name = name
        folder.createdAt = Date()
        try context.save()
        return folder
    }
    
    @MainActor
    func fetchFolders() async throws -> [FolderEntity] {
        let request = FolderEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \FolderEntity.createdAt, ascending: true)]
        return try context.fetch(request)
    }
    
    @MainActor
    func deleteFolder(_ folder: FolderEntity) async throws {
        context.delete(folder)
        try context.save()
    }
    
    @MainActor
    func updateFolder(_ folder: FolderEntity, name: String) async throws {
        folder.name = name
        try context.save()
    }
    
    // MARK: - Pin Operations
    
    @MainActor
    func createPin(
        name: String,
        latitude: Double,
        longitude: Double,
        iconName: String,
        folder: FolderEntity
    ) async throws -> PinEntity {
        let pin = PinEntity(context: context)
        pin.id = UUID()
        pin.name = name
        pin.latitude = latitude
        pin.longitude = longitude
        pin.iconName = iconName
        pin.dateCreated = Date()
        pin.folder = folder
        try context.save()
        
        NotificationCenter.default.post(name: .coreDataDidChange, object: nil)
        return pin
    }
    
    @MainActor
    func fetchPins(for folder: FolderEntity? = nil) async throws -> [PinEntity] {
        let request = PinEntity.fetchRequest()
        if let folder = folder {
            request.predicate = NSPredicate(format: "folder == %@", folder)
        }
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PinEntity.dateCreated, ascending: false)]
        return try context.fetch(request)
    }
    
    @MainActor
    func fetchAllPins() async throws -> [PinEntity] {
        let request = PinEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \PinEntity.dateCreated, ascending: false)]
        return try context.fetch(request)
    }
    
    @MainActor
    func updatePin(
        _ pin: PinEntity,
        name: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        iconName: String? = nil,
        serverPinId: String? = nil
    ) async throws {
        if let name = name { pin.name = name }
        if let latitude = latitude { pin.latitude = latitude }
        if let longitude = longitude { pin.longitude = longitude }
        if let iconName = iconName { pin.iconName = iconName }
        if let serverPinId = serverPinId { pin.serverPinId = serverPinId }
        try context.save()
        
        NotificationCenter.default.post(name: .coreDataDidChange, object: nil)
    }
    
    @MainActor
    func deletePin(_ pin: PinEntity) async throws {
        context.delete(pin)
        try context.save()
        
        NotificationCenter.default.post(name: .coreDataDidChange, object: nil)
    }
    
    @MainActor
    func movePin(_ pin: PinEntity, to folder: FolderEntity) async throws {
        pin.folder = folder
        try context.save()
        
        NotificationCenter.default.post(name: .coreDataDidChange, object: nil)
    }
    
    // MARK: - Field Operations
    
    @MainActor
    func createField(
        name: String,
        coordinates: [[String: Double]],
        acres: Double,
        color: String,
        category: String,
        application: String?,
        fieldDescription: String?,
        folder: FolderEntity
    ) async throws -> FieldEntity {
        let field = FieldEntity(context: context)
        field.id = UUID()
        field.name = name
        field.coordinatesData = try? JSONEncoder().encode(coordinates)
        field.acres = acres
        field.color = color
        field.category = category
        field.application = application
        field.fieldDescription = fieldDescription
        field.dateImported = Date()
        field.folder = folder
        try context.save()
        return field
    }
    
    @MainActor
    func fetchFields(for folder: FolderEntity? = nil) async throws -> [FieldEntity] {
        let request = FieldEntity.fetchRequest()
        if let folder = folder {
            request.predicate = NSPredicate(format: "folder == %@", folder)
        }
        request.sortDescriptors = [NSSortDescriptor(keyPath: \FieldEntity.dateImported, ascending: false)]
        return try context.fetch(request)
    }
    
    @MainActor
    func updateField(_ field: FieldEntity, name: String) async throws {
        field.name = name
        try context.save()
    }
    
    @MainActor
    func deleteField(_ field: FieldEntity) async throws {
        context.delete(field)
        try context.save()
    }
    
    // MARK: - Batch Operations
    
    @MainActor
    func deleteAllData() async throws {
        let folderRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FolderEntity")
        let deleteFolders = NSBatchDeleteRequest(fetchRequest: folderRequest)
        try context.execute(deleteFolders)
        
        let pinRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "PinEntity")
        let deletePins = NSBatchDeleteRequest(fetchRequest: pinRequest)
        try context.execute(deletePins)
        
        let fieldRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FieldEntity")
        let deleteFields = NSBatchDeleteRequest(fetchRequest: fieldRequest)
        try context.execute(deleteFields)
        
        try context.save()
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let coreDataDidChange = Notification.Name("coreDataDidChange")
}
