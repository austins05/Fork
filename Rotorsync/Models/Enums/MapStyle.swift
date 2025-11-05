import Foundation
import MapKit

enum AppMapStyle: String, CaseIterable, Hashable {
    case standard
    case imagery
    case hybrid
    
    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .imagery: return "Imagery"
        case .hybrid: return "Hybrid"
        }
    }
    
    var mapType: MKMapType {
        switch self {
        case .standard: return .standard
        case .imagery: return .satellite
        case .hybrid: return .hybrid
        }
    }
}
