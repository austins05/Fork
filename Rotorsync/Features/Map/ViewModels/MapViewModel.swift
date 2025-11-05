import Foundation
import Combine
import CoreLocation
import MapKit

@MainActor
final class MapViewModel: ObservableObject {
    @Published var devices: [Device] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isMQTTStarted = false

    private var cancellables = Set<AnyCancellable>()

    init() {}

    func fetchDevices() async {
        isLoading = true
        errorMessage = nil

        guard let url = URL(string: "https://rotorsync-web.vercel.app/api/devices") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = KeychainService.getToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(DeviceResponse.self, from: data)

            if decoded.success {
                devices = decoded.data
                
                // Only start MQTT once
                if !isMQTTStarted {
                    startMQTT(with: decoded.data)
                    isMQTTStarted = true
                }
            } else {
                errorMessage = decoded.error ?? "Unknown server error"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func startMQTT(with devices: [Device]) {
        // Check if already connected
        if MQTTManager.shared.isConnected {
            print("ℹ️ MQTT already connected, skipping")
            return
        }
        
        let userSerial = getUserSerialNumber()
        let userDevice = devices.first { $0.serialNumber?.name == userSerial }

        MQTTManager.shared.start(with: devices, userDevice: userDevice)

        NotificationCenter.default.publisher(for: .deviceLocationUpdated)
            .sink { [weak self] notification in
                if let updated = notification.object as? Device,
                   let index = self?.devices.firstIndex(where: { $0.id == updated.id }) {
                    self?.devices[index] = updated
                }
            }
            .store(in: &cancellables)
    }

    private func getUserSerialNumber() -> String? {
        struct User: Codable {
            let serialNumber: SerialNumber?
            struct SerialNumber: Codable { let name: String }
        }
        
        guard let data = UserDefaults.standard.data(forKey: "userData"),
              let user = try? JSONDecoder().decode(User.self, from: data) else {
            return nil
        }
        return user.serialNumber?.name
    }

    func regionIncludingAll(userLocation: CLLocationCoordinate2D?) -> MKCoordinateRegion? {
        let deviceCoords = devices.compactMap { device -> CLLocationCoordinate2D? in
            guard let lat = device.latitude, let lon = device.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        var all = deviceCoords
        if let user = userLocation { all.append(user) }

        guard !all.isEmpty else { return nil }

        let lats = all.map { $0.latitude }
        let lons = all.map { $0.longitude }

        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let latΔ = max((maxLat - minLat) * 1.3, 0.005)
        let lonΔ = max((maxLon - minLon) * 1.3, 0.005)

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latΔ, longitudeDelta: lonΔ)
        )
    }
}
