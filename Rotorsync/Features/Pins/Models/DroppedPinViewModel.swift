import Foundation
import CoreLocation

struct DroppedPinViewModel: Identifiable, Hashable, Equatable {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
    let iconName: String
    let isShared: Bool  // Add this property
    
    init(id: UUID, name: String, coordinate: CLLocationCoordinate2D, iconName: String, isShared: Bool = false) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.iconName = iconName
        self.isShared = isShared
    }
    
    init(from entity: PinEntity) {
        self.id = entity.id ?? UUID()
        self.name = entity.name ?? "Unknown Pin"
        self.coordinate = entity.coordinate
        self.iconName = entity.iconName ?? "mappin"
        self.isShared = entity.serverPinId != nil  // Check if synced to server
    }
    
    static func == (lhs: DroppedPinViewModel, rhs: DroppedPinViewModel) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.iconName == rhs.iconName &&
        lhs.isShared == rhs.isShared
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(iconName)
        hasher.combine(isShared)
    }
}
