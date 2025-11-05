import Foundation

struct User: Codable {
    let id: String
    let name: String
    let email: String
    let role: String
    let serialNumber: SerialNumber?

    struct SerialNumber: Codable {
        let id: String
        let assetType: String
        let name: String
        let serialNumber: String
    }
}
