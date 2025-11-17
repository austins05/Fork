//
//  NavigationState.swift
//  Rotorsync
//
//  Created on 11/15/25.
//

import Foundation
import MapKit

// MARK: - Navigation Route
struct NavigationRoute: Identifiable, Equatable {
    let id = UUID()
    let route: MKRoute
    let name: String
    let distance: Double // meters
    let expectedTravelTime: TimeInterval // seconds
    let combinedPolyline: MKPolyline? // For multi-segment waypoint routes
    let routeSegments: [MKRoute]? // Store all segments for waypoint routes

    var distanceString: String {
        let miles = distance / 1609.34
        return String(format: "%.1f mi", miles)
    }

    var timeString: String {
        let minutes = Int(expectedTravelTime / 60)
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }

    static func == (lhs: NavigationRoute, rhs: NavigationRoute) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Navigation Step
struct NavigationStep {
    let instruction: String
    let distance: Double // meters to this step
    let polyline: MKPolyline
    let notice: String?

    var distanceString: String {
        let feet = distance * 3.28084
        if feet < 528 { // Less than 0.1 miles
            return String(format: "%.0f ft", feet)
        } else {
            let miles = distance / 1609.34
            return String(format: "%.1f mi", miles)
        }
    }
}

// MARK: - Navigation Status
enum NavigationStatus: Equatable {
    case idle
    case calculatingRoute
    case selectingRoute([NavigationRoute])
    case navigating
    case rerouting
    case arrived
    case error(String)

    static func == (lhs: NavigationStatus, rhs: NavigationStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.calculatingRoute, .calculatingRoute),
             (.navigating, .navigating),
             (.rerouting, .rerouting),
             (.arrived, .arrived):
            return true
        case (.selectingRoute(let lRoutes), .selectingRoute(let rRoutes)):
            return lRoutes == rRoutes
        case (.error(let lMsg), .error(let rMsg)):
            return lMsg == rMsg
        default:
            return false
        }
    }
}

// MARK: - Navigation Settings
struct NavigationSettings {
    var avoidHighways: Bool = false
    var voiceGuidanceEnabled: Bool = true

    static let avoidHighwaysKey = "navigation_avoid_highways"
    static let voiceGuidanceKey = "navigation_voice_guidance"

    static func load() -> NavigationSettings {
        let defaults = UserDefaults.standard

        // Check if values exist, otherwise use defaults
        let avoidHighways = defaults.object(forKey: avoidHighwaysKey) as? Bool ?? false
        let voiceGuidanceEnabled = defaults.object(forKey: voiceGuidanceKey) as? Bool ?? true

        return NavigationSettings(
            avoidHighways: avoidHighways,
            voiceGuidanceEnabled: voiceGuidanceEnabled
        )
    }

    func save() {
        UserDefaults.standard.set(avoidHighways, forKey: NavigationSettings.avoidHighwaysKey)
        UserDefaults.standard.set(voiceGuidanceEnabled, forKey: NavigationSettings.voiceGuidanceKey)
    }
}
