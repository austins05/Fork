//
//  FlyToView.swift
//  Rotorsync
//
//  Created on 11/15/25.
//

import SwiftUI
import CoreLocation

struct FlyToView: View {
    let destination: CLLocationCoordinate2D
    let currentLocation: CLLocation?
    @Binding var isFlyingTo: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "airplane")
                        .font(.title2)
                        .foregroundColor(.green)

                    Text("Fly To")
                        .font(.headline)
                        .fontWeight(.bold)

                    Spacer()

                    Button(action: { isFlyingTo = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.red)
                    }
                }
                .padding()
                .background(Color(.systemGray6))

                if let location = currentLocation {
                    // Distance
                    VStack(spacing: 8) {
                        Text("Distance")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(distanceString(from: location))
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.green)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()

                    Divider()

                    // Bearing/Direction
                    VStack(spacing: 8) {
                        Text("Bearing")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            Image(systemName: "location.north.fill")
                                .font(.title)
                                .foregroundColor(.green)
                                .rotationEffect(.degrees(bearingAngle(from: location)))

                            Text(bearingString(from: location))
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    Text("Waiting for location...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding()
                }

                Spacer()
            }
            .frame(width: 280)
            .background(Color(.systemBackground))
            .shadow(color: .black.opacity(0.2), radius: 10, x: 2, y: 0)

            Spacer()
        }
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

    private func bearingAngle(from location: CLLocation) -> Double {
        let destLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)

        let lat1 = location.coordinate.latitude * .pi / 180
        let lon1 = location.coordinate.longitude * .pi / 180
        let lat2 = destLocation.coordinate.latitude * .pi / 180
        let lon2 = destLocation.coordinate.longitude * .pi / 180

        let dLon = lon2 - lon1

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi

        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    private func bearingString(from location: CLLocation) -> String {
        let bearing = bearingAngle(from: location)

        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((bearing + 22.5) / 45) % 8
        return "\(directions[index]) \(Int(bearing))°"
    }
}

#Preview {
    FlyToView(
        destination: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
        currentLocation: CLLocation(latitude: 40.0, longitude: -73.0),
        isFlyingTo: .constant(true)
    )
}
