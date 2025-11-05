import Foundation

struct APIGroup: Codable {
    let id: String
    let name: String
    let description: String?
    let createdAt: String
    let updatedAt: String
    
    struct MemberInfo: Codable {
        let role: String
    }
    
    struct CountInfo: Codable {
        let members: Int
        let pins: Int
    }
    
    let members: [MemberInfo]?
    let _count: CountInfo?
}
