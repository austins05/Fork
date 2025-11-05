import Foundation

struct Device: Identifiable, Codable, Equatable {
    let id: String
    let deviceId: String
    let name: String
    var latitude: Double?
    var longitude: Double?
    let displayName: String
    let assetType: String?
    let lineColor: String?
    let serialNumber: SerialNumber?
    let mqttTopic: String?

    struct SerialNumber: Codable {
        let name: String
    }

    static func == (lhs: Device, rhs: Device) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - API Response
struct DeviceResponse: Codable {
    let success: Bool
    let data: [Device]
    let error: String?
}
