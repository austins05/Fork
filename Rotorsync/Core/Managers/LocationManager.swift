import UIKit
import Foundation
import CoreLocation
import Combine

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    
    private let manager = CLLocationManager()
    
    // Published for UI
    @Published var userLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    private override init() {
        super.init()
        setupLocationManager()
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
    
    // MARK: - Permission Management
    
    func requestLocationPermission() {
        manager.requestAlwaysAuthorization()
    }
    
    private func requestPermissionAndStart() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestAlwaysAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            startUpdating()
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
                self.startUpdating()
            case .authorizedWhenInUse:
                self.startUpdating()
            case .denied, .restricted:
                print("Location access denied")
            default:
                break
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        userLocation = location
        Task { @MainActor in MQTTManager.shared.publishUserLocation(location) }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
    
    // MARK: - Helpers for UI
    
    var speedString: String {
        guard let speed = userLocation?.speed, speed >= 0 else { return "—" }
        return String(format: "%.1f mph", speed * 2.23694)
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
}
