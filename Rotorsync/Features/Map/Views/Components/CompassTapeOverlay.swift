//
//  CompassTapeOverlay.swift
//  Rotorsync
//
//  Created on 11/15/25.
//

import SwiftUI
import CoreLocation

struct CompassTapeOverlay: View {
    let currentHeading: Double
    let destinationBearing: Double?
    let destination: CLLocationCoordinate2D
    let currentLocation: CLLocation?
    @Binding var isFlyingTo: Bool
    let averageSpeed: Double // m/s
    var onEndFlyTo: (() -> Void)?

    var body: some View {
        // Centered compact bar at top
        HStack(spacing: 12) {
            // Distance
            if let location = currentLocation {
                VStack(spacing: 2) {
                    Text("DIST")
                        .font(.caption2.bold())
                        .foregroundColor(.white.opacity(0.7))
                    Text(distanceString(from: location))
                        .font(.subheadline.bold())
                        .foregroundColor(.green)
                }
                .frame(width: 55)
            }

            // Compass degree marks - CENTERED
            GeometryReader { geometry in
                ZStack {
                    // Scrolling degree marks
                    DegreeTapeView(currentHeading: currentHeading)

                    // Center reference line (your heading/nose)
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: geometry.size.height * 0.6)
                        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.7)

                    // Destination bearing marker
                    if let bearing = destinationBearing {
                        let relativeBearing = normalizeAngle(bearing - currentHeading)
                        let offsetPerDegree = geometry.size.width / 60.0
                        let markerOffset = relativeBearing * offsetPerDegree

                        // Always show marker, make it bigger and more visible
                        VStack(spacing: 0) {
                            Image(systemName: "arrowtriangle.down.fill")
                                .foregroundColor(.green)
                                .font(.title3)
                            Text("\(Int(bearing))°")
                                .font(.caption2.bold())
                                .foregroundColor(.green)
                        }
                        .position(x: geometry.size.width / 2 + markerOffset, y: 10)
                    }
                }
            }
            .frame(width: 280, height: 40) // Wider compass tape

            // ETA
            if let location = currentLocation {
                VStack(spacing: 2) {
                    Text("ETA")
                        .font(.caption2.bold())
                        .foregroundColor(.white.opacity(0.7))
                    Text(etaString(from: location))
                        .font(.subheadline.bold())
                        .foregroundColor(.cyan)
                }
                .frame(width: 55)
            }

            // Close button
            Button(action: {
                print("❌ [FLY TO] X BUTTON PRESSED")
                if let callback = onEndFlyTo {
                    print("❌ [FLY TO] Calling onEndFlyTo callback")
                    callback()
                } else {
                    print("❌ [FLY TO] No callback, setting isFlyingTo = false")
                    isFlyingTo = false
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.8))
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.75))
        .cornerRadius(12)
        .shadow(radius: 5)
        .frame(maxWidth: .infinity) // Take full width to center properly
        .padding(.top, 80) // Moved down more - under tab bar
    }

    private func normalizeAngle(_ angle: Double) -> Double {
        var normalized = angle
        while normalized > 180 { normalized -= 360 }
        while normalized < -180 { normalized += 360 }
        return normalized
    }

    private func distanceString(from location: CLLocation) -> String {
        let destLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let distance = location.distance(from: destLocation)
        let miles = distance / 1609.34

        if miles < 0.1 {
            return String(format: "%.0f ft", distance * 3.28084)
        } else {
            return String(format: "%.1f mi", miles)
        }
    }

    private func etaString(from location: CLLocation) -> String {
        let destLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let distance = location.distance(from: destLocation)

        guard averageSpeed > 0.5 else { // Less than 0.5 m/s (1.1 mph) - too slow
            return "--:--"
        }

        let timeSeconds = distance / averageSpeed
        let arrivalDate = Date().addingTimeInterval(timeSeconds)

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: arrivalDate)
    }
}

struct DegreeTapeView: View {
    let currentHeading: Double

    var body: some View {
        GeometryReader { geometry in
            let degreesPerPoint = 60.0 / geometry.size.width
            let centerOffset = currentHeading

            Canvas { context, size in
                for degree in stride(from: 0, through: 360, by: 5) {
                    let relativeDegree = normalizeAngle(Double(degree) - centerOffset)

                    if abs(relativeDegree) <= 35 {
                        let xPosition = size.width / 2 + (relativeDegree / degreesPerPoint)

                        if degree % 10 == 0 {
                            // Major tick
                            let tickPath = Path { path in
                                path.move(to: CGPoint(x: xPosition, y: size.height * 0.5))
                                path.addLine(to: CGPoint(x: xPosition, y: size.height - 4))
                            }
                            context.stroke(tickPath, with: .color(.white.opacity(0.8)), lineWidth: 1.5)

                            // Label
                            let text = Text("\(degree)°")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                            context.draw(text, at: CGPoint(x: xPosition, y: size.height * 0.25))
                        } else {
                            // Minor tick
                            let tickPath = Path { path in
                                path.move(to: CGPoint(x: xPosition, y: size.height * 0.65))
                                path.addLine(to: CGPoint(x: xPosition, y: size.height - 4))
                            }
                            context.stroke(tickPath, with: .color(.white.opacity(0.5)), lineWidth: 1)
                        }
                    }
                }
            }
        }
    }

    private func normalizeAngle(_ angle: Double) -> Double {
        var normalized = angle
        while normalized > 180 { normalized -= 360 }
        while normalized < -180 { normalized += 360 }
        return normalized
    }
}

#Preview {
    ZStack {
        Color.gray.ignoresSafeArea()
        VStack {
            CompassTapeOverlay(
                currentHeading: 45,
                destinationBearing: 75,
                destination: CLLocationCoordinate2D(latitude: 40, longitude: -90),
                currentLocation: CLLocation(latitude: 39, longitude: -89),
                isFlyingTo: .constant(true),
                averageSpeed: 13.4, // ~30 mph
                onEndFlyTo: {}
            )
            Spacer()
        }
    }
}
