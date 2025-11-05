import Foundation
import CoreLocation

struct APIPin: Codable, Identifiable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let iconName: String
    let groupId: String?
    let folderId: String?
    let createdBy: String
    let createdAt: String
    let updatedAt: String
    
    struct Creator: Codable {
        let id: String
        let name: String
        let email: String
    }
    
    let creator: Creator?
    
    enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, iconName, groupId, folderId, createdBy, createdAt, updatedAt, creator
    }
}
