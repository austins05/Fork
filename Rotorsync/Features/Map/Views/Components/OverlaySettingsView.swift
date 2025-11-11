import SwiftUI

enum TemperatureGraphPosition: String, CaseIterable {
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"

    var coordinates: CGPoint {
        switch self {
        case .topLeft:
            return CGPoint(x: 150, y: 220)
        case .topRight:
            return CGPoint(x: 650, y: 220)
        case .bottomLeft:
            return CGPoint(x: 150, y: 650)
        case .bottomRight:
            return CGPoint(x: 650, y: 650)
        }
    }
}

struct OverlaySettingsView: View {
    @Binding var overlayScale: CGFloat
    @Binding var shareLocation: Bool
    @Binding var showTemperatureGraph: Bool
    @Binding var temperatureGraphPosition: TemperatureGraphPosition
    @Binding var temperatureGraphScale: CGFloat
    @Binding var mapStyle: AppMapStyle

    var body: some View {
        VStack(spacing: 12) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.bottom, 5)

            // Map Style Section
            VStack(alignment: .leading, spacing: 6) {
                Text("Map Style")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    ForEach(AppMapStyle.allCases, id: \.self) { style in
                        Button {
                            mapStyle = style
                        } label: {
                            Text(style.displayName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(mapStyle == style ? .white : .blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(mapStyle == style ? Color.blue : Color.blue.opacity(0.1))
                                )
                        }
                    }
                }
            }
            .padding(.horizontal, 20)

            Divider()
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 6) {
                Text("Overlay Size (\(String(format: "%.1f", overlayScale))x)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Slider(value: $overlayScale, in: 0.7...1.6, step: 0.1)
                    .tint(.blue)

                HStack {
                    Text("XS")
                    Spacer()
                    Text("XL")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)

            HStack {
                Text("Share My Location")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Toggle("", isOn: $shareLocation)
                    .labelsHidden()
                    .tint(.blue)
            }
            .padding(.horizontal, 20)

            HStack {
                Text("Show Temperature Graph")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Toggle("", isOn: $showTemperatureGraph)
                    .labelsHidden()
                    .tint(.blue)
            }
            .padding(.horizontal, 20)

            if showTemperatureGraph {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Graph Position")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        ForEach(TemperatureGraphPosition.allCases, id: \.self) { position in
                            Button {
                                temperatureGraphPosition = position
                            } label: {
                                Text(position.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(temperatureGraphPosition == position ? .white : .blue)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(temperatureGraphPosition == position ? Color.blue : Color.blue.opacity(0.1))
                                    )
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Graph Size (\(String(format: "%.1f", temperatureGraphScale))x)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Slider(value: $temperatureGraphScale, in: 0.7...1.5, step: 0.1)
                        .tint(.blue)

                    HStack {
                        Text("Small")
                        Spacer()
                        Text("Large")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}
