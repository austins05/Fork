import Foundation

struct GroupMember: Codable, Identifiable {
    let id: String
    let userId: String
    let groupId: String
    let role: String
    
    struct UserInfo: Codable {
        let id: String
        let name: String
        let email: String
        let role: String
    }
    
    let user: UserInfo
}
