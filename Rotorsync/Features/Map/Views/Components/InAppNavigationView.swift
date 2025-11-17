//
//  InAppNavigationView.swift
//  Rotorsync
//
//  Created on 11/15/25.
//

import SwiftUI
import MapKit

struct InAppNavigationView: View {
    @ObservedObject var navigationManager: NavigationManager
    @Binding var isNavigating: Bool
    var onEndNavigation: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("Navigation")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    Button(action: {
                        print("❌ [NAV UI] X BUTTON PRESSED")
                        if let callback = onEndNavigation {
                            print("❌ [NAV UI] Calling onEndNavigation callback")
                            callback()
                        } else {
                            print("❌ [NAV UI] No callback, setting isNavigating = false")
                            isNavigating = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.red)
                    }
                }
                .padding()
                .background(Color(.systemGray6))

                // Current maneuver section
                if let instruction = navigationManager.currentStep?.instruction {
                    VStack(spacing: 16) {
                        // Large maneuver arrow
                        Image(systemName: maneuverIcon(for: instruction))
                            .font(.system(size: 80))
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 20)

                        // Distance to turn
                        Text(distanceString(navigationManager.distanceToNextStep))
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)

                        // Instruction text
                        Text(instruction)
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground))
                }

                Divider()

                // Next turn preview
                if let nextInstruction = navigationManager.nextStep?.instruction,
                   !nextInstruction.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: maneuverIcon(for: nextInstruction))
                            .foregroundColor(.gray)
                            .frame(width: 30)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Then")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(nextInstruction)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(Color(.systemGray6))
                }

                Divider()

                // Trip statistics
                VStack(spacing: 0) {
                    StatRow(
                        icon: "clock",
                        label: "ETA",
                        value: etaString(navigationManager.remainingTime)
                    )
                    .padding()

                    Divider()

                    StatRow(
                        icon: "road.lanes",
                        label: "Remaining",
                        value: distanceString(navigationManager.remainingDistance)
                    )
                    .padding()
                }
                .background(Color(.systemBackground))

                Divider()

                Spacer()

                // Settings toggles at bottom
                VStack(spacing: 12) {
                    // Highway avoidance toggle
                    Toggle(isOn: Binding(
                        get: { NavigationSettings.load().avoidHighways },
                        set: { newValue in
                            var settings = NavigationSettings.load()
                            settings.avoidHighways = newValue
                            settings.save()
                            navigationManager.updateSettings(settings)
                        }
                    )) {
                        HStack(spacing: 12) {
                            Image(systemName: "road.lanes.curved.right")
                                .font(.title3)
                            Text("Avoid Highways")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.primary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)

                    // Voice guidance toggle
                    Button(action: { navigationManager.toggleVoiceGuidance() }) {
                        HStack(spacing: 12) {
                            Image(systemName: navigationManager.voiceGuidanceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.title3)
                            Text(navigationManager.voiceGuidanceEnabled ? "Voice Guidance On" : "Voice Guidance Off")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        .foregroundColor(navigationManager.voiceGuidanceEnabled ? .blue : .gray)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                }
                .padding()
            }
            .frame(width: 280)
            .background(Color(.systemBackground))
            .shadow(color: .black.opacity(0.2), radius: 10, x: 2, y: 0)

            Spacer()
        }
    }

    private func maneuverIcon(for instruction: String) -> String {
        let lower = instruction.lowercased()

        if lower.contains("left") && lower.contains("slight") {
            return "arrow.turn.up.left"
        } else if lower.contains("right") && lower.contains("slight") {
            return "arrow.turn.up.right"
        } else if lower.contains("left") && lower.contains("sharp") {
            return "arrow.uturn.left"
        } else if lower.contains("right") && lower.contains("sharp") {
            return "arrow.uturn.right"
        } else if lower.contains("turn left") {
            return "arrow.left"
        } else if lower.contains("turn right") {
            return "arrow.right"
        } else if lower.contains("straight") || lower.contains("continue") {
            return "arrow.up"
        } else if lower.contains("u-turn") || lower.contains("uturn") {
            return "arrow.uturn.forward"
        } else if lower.contains("merge") {
            return "arrow.triangle.merge"
        } else if lower.contains("roundabout") {
            return "arrow.circlepath"
        } else if lower.contains("exit") {
            return "arrow.uturn.right"
        } else {
            return "arrow.up.circle"
        }
    }

    private func distanceString(_ meters: Double) -> String {
        let feet = meters * 3.28084

        if feet < 528 {
            return String(format: "%.0f ft", feet)
        } else {
            let miles = meters / 1609.34
            return String(format: "%.1f mi", miles)
        }
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)

        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }

    private func etaString(_ remainingSeconds: TimeInterval) -> String {
        let arrivalDate = Date().addingTimeInterval(remainingSeconds)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: arrivalDate)
    }
}

// MARK: - Supporting Views
struct StatRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
    }
}

// Helper for custom corner radius
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()

        InAppNavigationView(
            navigationManager: NavigationManager(locationManager: LocationManager.shared),
            isNavigating: .constant(true)
        )
    }
}
