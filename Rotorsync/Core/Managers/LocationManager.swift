import UIKit
import Foundation
import CoreLocation
import Combine

// MARK: - GPS Source Type

enum GPSSource: String, Codable {
    case internal_ = "internal"
    case tcp = "tcp"
}

// MARK: - GPS Settings

struct GPSSettings: Codable {
    var source: GPSSource = .internal_
    var tcpHost: String = ""
    var tcpPort: UInt16 = 10110
    var tcpEnabled: Bool = false
    
    static func load() -> GPSSettings {
        guard let data = UserDefaults.standard.data(forKey: "gpsSettings"),
              let settings = try? JSONDecoder().decode(GPSSettings.self, from: data) else {
            return GPSSettings()
        }
        return settings
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "gpsSettings")
        }
    }
}

// MARK: - Location Manager

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    
    private let manager = CLLocationManager()
    private let tcpClient = TCPGPSClient()
    private var cancellables = Set<AnyCancellable>()
    
    // Published for UI
    @Published var userLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var gpsSettings = GPSSettings.load()
    @Published var gpsSource: GPSSource = .internal_
    
    private override init() {
        super.init()
        setupLocationManager()
        setupTCPGPSObserver()
        applyGPSSettings()
    }
    
    // MARK: - Setup
    
    private func setupLocationManager() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone // Update at maximum frequency (~10Hz)
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .automotiveNavigation

        // Critical for background
        manager.showsBackgroundLocationIndicator = true
        
        authorizationStatus = manager.authorizationStatus
        requestPermissionAndStart()
    }
    
    private func setupTCPGPSObserver() {
        // Observe TCP GPS location updates
        tcpClient.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                guard let self = self else { return }
                // Only use TCP location if TCP is enabled
                if self.gpsSettings.tcpEnabled {
                    print("[LocationManager] 📡 Received TCP GPS update: lat=\(location.coordinate.latitude), lon=\(location.coordinate.longitude), speed=\(location.speed)m/s (\(location.speed * 2.23694)mph), course=\(location.course)°")
                    self.userLocation = location
                    print("[LocationManager] ✅ Set userLocation to TCP GPS data")
                    Task { @MainActor in 
                        MQTTManager.shared.publishUserLocation(location) 
                        print("[LocationManager] 📤 Published TCP GPS location to MQTT")
                    }
                } else {
                    print("[LocationManager] ⚠️ TCP GPS data received but TCP is disabled - ignoring")
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - GPS Source Management
    
    func applyGPSSettings() {
        gpsSettings = GPSSettings.load()
        
        if gpsSettings.tcpEnabled && !gpsSettings.tcpHost.isEmpty {
            // Enable TCP GPS
            gpsSource = .tcp
            tcpClient.connect(host: gpsSettings.tcpHost, port: gpsSettings.tcpPort)
            // Stop internal GPS to save battery
            stopUpdating()
            print("[LocationManager] Switched to TCP GPS: \(gpsSettings.tcpHost):\(gpsSettings.tcpPort)")
        } else {
            // Use internal GPS
            gpsSource = .internal_
            tcpClient.disconnect()
            // Ensure internal GPS is running
            if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
                startUpdating()
            }
            print("[LocationManager] Using internal GPS")
        }
    }
    
    func updateGPSSettings(_ settings: GPSSettings) {
        settings.save()
        applyGPSSettings()
    }
    
    // MARK: - Permission Management
    
    func requestLocationPermission() {
        manager.requestAlwaysAuthorization()
    }
    
    private func requestPermissionAndStart() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestAlwaysAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            // Only start if not using TCP
            if !gpsSettings.tcpEnabled {
                startUpdating()
            }
        default:
            break
        }
    }
    
    private func startUpdating() {
        manager.startUpdatingLocation()
        manager.startMonitoringSignificantLocationChanges()
    }
    
    func stopUpdating() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        
        DispatchQueue.main.async {
            switch self.authorizationStatus {
            case .authorizedAlways:
                // Only start if not using TCP
                if !self.gpsSettings.tcpEnabled {
                    self.startUpdating()
                }
            case .authorizedWhenInUse:
                if !self.gpsSettings.tcpEnabled {
                    self.startUpdating()
                }
            case .denied, .restricted:
                print("Location access denied")
            default:
                break
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Only use internal GPS location if TCP is not enabled
        if !gpsSettings.tcpEnabled {
            userLocation = location
            Task { @MainActor in MQTTManager.shared.publishUserLocation(location) }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
    
    // MARK: - Helpers for UI
    
    var speedString: String {
        print("[LocationManager] speedString called:")
        print("  userLocation exists: \(userLocation != nil)")
        if let location = userLocation {
            print("  userLocation.speed: \(location.speed) m/s")
            print("  speed >= 0: \(location.speed >= 0)")
        }
        
        guard let speed = userLocation?.speed, speed >= 0 else { 
            print("  Returning '—' (no valid speed)")
            return "—" 
        }
        
        let mph = speed * 2.23694
        let result = String(format: "%.1f mph", mph)
        print("  Returning: \(result)")
        return result
    }
    
    var altitudeString: String {
        guard let altitude = userLocation?.altitude else { return "—" }
        return String(format: "%.0f ft", altitude * 3.28084)
    }
    
    var coordinateString: String {
        guard let location = userLocation else { return "—" }
        return String(format: "%.6f, %.6f", location.coordinate.latitude, location.coordinate.longitude)
    }
    
    var accuracyString: String {
        guard let accuracy = userLocation?.horizontalAccuracy else { return "—" }
        return String(format: "±%.0f m", accuracy)
    }
    
    var sourceString: String {
        switch gpsSource {
        case .internal_:
            return "Internal GPS"
        case .tcp:
            return "TCP GPS (\(gpsSettings.tcpHost):\(gpsSettings.tcpPort))"
        }
    }
    
    // MARK: - Distance Calculations
    
    func distance(from coordinate: CLLocationCoordinate2D) -> Double? {
        guard let userLocation = userLocation else { return nil }
        let targetLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return userLocation.distance(from: targetLocation)
    }
    
    func distanceString(from coordinate: CLLocationCoordinate2D) -> String {
        guard let distance = distance(from: coordinate) else { return "—" }
        
        // Convert to miles
        let miles = distance / 1609.34
        
        if miles < 0.1 {
            // Show in feet for very short distances
            return String(format: "%.0f ft", distance * 3.28084)
        } else {
            return String(format: "%.1f mi", miles)
        }
    }
    
    // MARK: - TCP GPS Access
    
    var tcpGPSClient: TCPGPSClient {
        return tcpClient
    }
}
