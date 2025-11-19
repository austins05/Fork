import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        // Initialize remote logger immediately
        _ = RemoteLogger.shared
        
        // Start MQTT immediately on app launch
        Task {
            await startMQTTIfLoggedIn()
        }
        
        return true
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        // Reconnect MQTT when app comes to foreground
        Task {
            await startMQTTIfLoggedIn()
        }
    }
    
    private func startMQTTIfLoggedIn() async {
        // Check if user is logged in
        guard KeychainService.hasToken(),
              let _ = UserDefaults.standard.data(forKey: "userData") else {
            print("User not logged in, skipping MQTT")
            return
        }
        
        // Fetch devices and start MQTT
        do {
            let devices = try await PinSyncService.shared.fetchDevices()
            
            // Get user's device
            let userSerial = getUserSerialNumber()
            let userDevice = devices.first { $0.serialNumber?.name == userSerial }
            
            await MainActor.run {
                MQTTManager.shared.start(with: devices, userDevice: userDevice)
            }
            
            print("✅ MQTT started automatically")
        } catch {
            print("❌ Failed to start MQTT: \(error)")
        }
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
}
