import SwiftUI
import CoreLocation

struct CrosshairOverlay: View {
    let userLocation: CLLocation?
    let mapCenter: CLLocationCoordinate2D?
    
    private var distanceString: String {
        guard let user = userLocation,
              let center = mapCenter else {
            return "—"
        }
        
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let distance = user.distance(from: centerLocation)
        let miles = distance / 1609.34
        
        if miles < 0.1 {
            return String(format: "%.0f ft", distance * 3.28084)
        } else {
            return String(format: "%.1f mi", miles)
        }
    }
    
    private var bearingString: String {
        guard let user = userLocation,
              let center = mapCenter else {
            return "—"
        }
        
        // Calculate bearing from user to center
        let lat1 = user.coordinate.latitude * .pi / 180
        let lon1 = user.coordinate.longitude * .pi / 180
        let lat2 = center.latitude * .pi / 180
        let lon2 = center.longitude * .pi / 180
        
        let dLon = lon2 - lon1
        
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        
        var bearing = atan2(y, x) * 180 / .pi
        bearing = (bearing + 360).truncatingRemainder(dividingBy: 360)
        
        // Get compass direction
        let direction = getCompassDirection(bearing: bearing)
        
        return String(format: "%.0f° %@", bearing, direction)
    }
    
    private func getCompassDirection(bearing: Double) -> String {
        switch bearing {
        case 0..<22.5: return "N"
        case 22.5..<67.5: return "NE"
        case 67.5..<112.5: return "E"
        case 112.5..<157.5: return "SE"
        case 157.5..<202.5: return "S"
        case 202.5..<247.5: return "SW"
        case 247.5..<292.5: return "W"
        case 292.5..<337.5: return "NW"
        case 337.5...360: return "N"
        default: return "—"
        }
    }
    
    var body: some View {
        VStack {
            Spacer()
            
            // Just the badge - no crosshair lines
            HStack(spacing: 6) {
                // Distance
                Text(distanceString)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                
                // Separator
                Text("|")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                
                // Bearing and direction
                Text(bearingString)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.red.opacity(0.9))
                    .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
            )
            .padding(.bottom, 50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
