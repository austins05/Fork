import Foundation
import UIKit
import CoreLocation

class MapUtilities {
    static func openInGoogleMaps(coordinate: CLLocationCoordinate2D, label: String? = nil) {
        var urlString = "comgooglemaps://?q=\(coordinate.latitude),\(coordinate.longitude)"
        
        if let label = label {
            let encodedLabel = label.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? label
            urlString += "&label=\(encodedLabel)"
        }
        
        urlString += "&center=\(coordinate.latitude),\(coordinate.longitude)&zoom=14"
        
        if let googleURL = URL(string: urlString),
           UIApplication.shared.canOpenURL(googleURL) {
            UIApplication.shared.open(googleURL)
            print("✅ Opened in Google Maps")
        } else {
            // Fallback to Apple Maps
            let appleURL = URL(string: "maps://?q=\(coordinate.latitude),\(coordinate.longitude)")!
            UIApplication.shared.open(appleURL)
            print("ℹ️ Google Maps not installed, opened in Apple Maps")
        }
    }
}
