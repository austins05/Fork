//
//  RouteSelectionSheet.swift
//  Rotorsync
//
//  Created on 11/15/25.
//

import SwiftUI
import MapKit

struct RouteSelectionSheet: View {
    @ObservedObject var navigationManager: NavigationManager
    @Binding var selectedRouteIndex: Int?
    @Binding var isAddingWaypoint: Bool
    let onStartNavigation: () -> Void
    let onCancel: () -> Void
    let onRecalculateRoutes: () -> Void
    @State private var avoidHighways: Bool = NavigationSettings.load().avoidHighways

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("Choose Route")
                        .font(.title2)
                        .fontWeight(.bold)

                    Spacer()

                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                .background(Color(.systemGray6))

                // Waypoint section
                VStack(alignment: .leading, spacing: 12) {
                    // Waypoint mode indicator (always active)
                    HStack(spacing: 10) {
                        Image(systemName: "hand.tap.fill")
                            .font(.title3)
                        Text("Tap map to add waypoint")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .foregroundColor(.green)
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(10)

                    // Waypoint list
                    if !navigationManager.waypoints.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(Array(navigationManager.waypoints.enumerated()), id: \.offset) { index, waypoint in
                                HStack {
                                    // Waypoint number circle
                                    ZStack {
                                        Circle()
                                            .fill(Color.blue)
                                            .frame(width: 28, height: 28)
                                        Text("\(index + 1)")
                                            .font(.caption.bold())
                                            .foregroundColor(.white)
                                    }

                                    Text("Waypoint \(index + 1)")
                                        .font(.subheadline)

                                    Spacer()

                                    Button(action: {
                                        navigationManager.removeWaypoint(at: index)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding()

                Divider()

                // Route options list
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(Array(navigationManager.availableRoutes.enumerated()), id: \.offset) { index, route in
                            RouteOptionCard(
                                route: route,
                                isSelected: selectedRouteIndex == index,
                                routeNumber: index + 1
                            ) {
                                selectedRouteIndex = index
                            }
                        }
                    }
                    .padding()
                }

                // Highway avoidance toggle
                Toggle(isOn: $avoidHighways) {
                    HStack(spacing: 10) {
                        Image(systemName: "road.lanes.curved.right")
                            .font(.subheadline)
                        Text("Avoid Highways")
                            .font(.subheadline)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .onChange(of: avoidHighways) { oldValue, newValue in
                    var settings = NavigationSettings.load()
                    settings.avoidHighways = newValue
                    settings.save()
                    navigationManager.updateSettings(settings)
                    print("🛣️ [ROUTE SETTINGS] Highway avoidance: \(newValue)")
                    onRecalculateRoutes()
                }

                // Start button
                if selectedRouteIndex != nil {
                    Button(action: onStartNavigation) {
                        HStack {
                            Spacer()
                            Text("Start Navigation")
                                .font(.headline)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding()
                }
            }
            .frame(width: 320)
            .background(Color(.systemBackground))
            .shadow(color: .black.opacity(0.2), radius: 10, x: 2, y: 0)

            Spacer()
        }
    }
}

struct RouteOptionCard: View {
    let route: NavigationRoute
    let isSelected: Bool
    let routeNumber: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    // Route color indicator
                    Circle()
                        .fill(routeColor)
                        .frame(width: 12, height: 12)

                    Text("Route \(routeNumber)")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title3)
                    }
                }

                // Route stats
                HStack(spacing: 20) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .foregroundColor(.blue)
                            .font(.caption)

                        Text(route.timeString)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "road.lanes")
                            .foregroundColor(.blue)
                            .font(.caption)

                        Text(route.distanceString)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }

                // Highway warning if applicable
                if hasHighways {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)

                        Text("Contains highways")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.15) : Color(.systemGray6))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var routeColor: Color {
        switch routeNumber {
        case 1:
            // Recommended route - bright blue
            return .blue
        case 2:
            // Alternate route - duller blue
            return Color.blue.opacity(0.7)
        case 3:
            // Third route - gray
            return .gray
        default:
            return .gray
        }
    }

    private var hasHighways: Bool {
        route.route.steps.contains { step in
            step.instructions.lowercased().contains("highway") ||
            step.instructions.lowercased().contains("interstate") ||
            step.instructions.lowercased().contains("freeway")
        }
    }
}

#Preview {
    RouteSelectionSheet(
        navigationManager: NavigationManager(locationManager: LocationManager.shared),
        selectedRouteIndex: .constant(0),
        isAddingWaypoint: .constant(false),
        onStartNavigation: {},
        onCancel: {},
        onRecalculateRoutes: {}
    )
}
