import SwiftUI
import MapKit
import CoreLocation

struct GroupPinDetailSheet: View {
    let pin: APIPin
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Pin Information") {
                    HStack {
                        Image(systemName: pin.iconName)
                            .foregroundColor(.red)
                            .frame(width: 30)
                        Text(pin.name)
                            .font(.headline)
                    }
                }
                
                Section("Location") {
                    HStack {
                        Text("Latitude")
                        Spacer()
                        Text(String(format: "%.6f", pin.latitude))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Longitude")
                        Spacer()
                        Text(String(format: "%.6f", pin.longitude))
                            .foregroundColor(.secondary)
                    }
                }
                
                if let creator = pin.creator {
                    Section("Created By") {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(creator.name)
                                    .font(.headline)
                                Text(creator.email)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack {
                            Text("Created")
                            Spacer()
                            Text(formatDate(pin.createdAt))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section {
                    Button {
                        driveToPin()
                    } label: {
                        Label("Drive To", systemImage: "car.fill")
                            .foregroundColor(.blue)
                    }
                    
                    Button {
                        showOnMap()
                    } label: {
                        Label("Show on Map", systemImage: "map.fill")
                            .foregroundColor(.blue)
                    }
                    
                    Button {
                        openInGoogleMaps()
                    } label: {
                        Label("Open in Google Maps", systemImage: "location.fill")
                            .foregroundColor(.green)
                    }
                }
            }
            .navigationTitle("Pin Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func showOnMap() {
        // Post notification to show pin on map
        NotificationCenter.default.post(
            name: .showGroupPinOnMap,
            object: pin
        )
        dismiss()
    }
    
    private func openInGoogleMaps() {
        let coordinate = CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
        
        // Try Google Maps first
        let googleURL = URL(string: "comgooglemaps://?q=\(coordinate.latitude),\(coordinate.longitude)&center=\(coordinate.latitude),\(coordinate.longitude)&zoom=14")!
        
        if UIApplication.shared.canOpenURL(googleURL) {
            UIApplication.shared.open(googleURL)
        } else {
            // Fallback to Apple Maps
            let appleURL = URL(string: "maps://?q=\(coordinate.latitude),\(coordinate.longitude)")!
            UIApplication.shared.open(appleURL)
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: date)
    }
    
    private func driveToPin() {
        let coordinate = CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
        
        let googleNavURL = URL(string: "comgooglemaps://?daddr=\(coordinate.latitude),\(coordinate.longitude)&directionsmode=driving")!
        
        if UIApplication.shared.canOpenURL(googleNavURL) {
            UIApplication.shared.open(googleNavURL)
        } else {
            let appleNavURL = URL(string: "maps://?daddr=\(coordinate.latitude),\(coordinate.longitude)&dirflg=d")!
            UIApplication.shared.open(appleNavURL)
        }
        dismiss()
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let showGroupPinOnMap = Notification.Name("showGroupPinOnMap")
}
