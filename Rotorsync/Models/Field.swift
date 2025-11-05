import Foundation
import CoreLocation

struct APIFolder: Codable {
    let id: String
    let name: String
    let groupId: String?
    let createdAt: String
    let updatedAt: String
    
    struct CountInfo: Codable {
        let pins: Int
    }
    
    let _count: CountInfo?
}
