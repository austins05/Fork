import SwiftUI

enum TemperatureGraphPosition: String, CaseIterable {
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"

    var coordinates: CGPoint {
        switch self {
        case .topLeft:
            return CGPoint(x: 150, y: 150)
        case .topRight:
            return CGPoint(x: 650, y: 150)
        case .bottomLeft:
            return CGPoint(x: 150, y: 650)
        case .bottomRight:
            return CGPoint(x: 650, y: 650)
        }
    }
}

enum TemperatureGraphSize: String, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"

    var size: CGSize {
        switch self {
        case .small:
            return CGSize(width: 200, height: 120)
        case .medium:
            return CGSize(width: 280, height: 180)
        case .large:
            return CGSize(width: 360, height: 240)
        }
    }
}

struct OverlaySettingsView: View {
    @Binding var overlayScale: CGFloat
    @Binding var shareLocation: Bool
    @Binding var showTemperatureGraph: Bool
    @Binding var temperatureGraphPosition: TemperatureGraphPosition
    @Binding var temperatureGraphSizePreset: TemperatureGraphSize

    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.bottom, 10)

            VStack(alignment: .leading) {
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
            .padding(.horizontal, 30)

            HStack {
                Text("Share My Location")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Toggle("", isOn: $shareLocation)
                    .labelsHidden()
                    .tint(.blue)
            }
            .padding(.horizontal, 30)

            HStack {
                Text("Show Temperature Graph")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Toggle("", isOn: $showTemperatureGraph)
                    .labelsHidden()
                    .tint(.blue)
            }
            .padding(.horizontal, 30)

            if showTemperatureGraph {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Graph Position")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 30)

                    HStack(spacing: 10) {
                        ForEach(TemperatureGraphPosition.allCases, id: \.self) { position in
                            Button {
                                temperatureGraphPosition = position
                            } label: {
                                Text(position.rawValue)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(temperatureGraphPosition == position ? .white : .blue)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(temperatureGraphPosition == position ? Color.blue : Color.blue.opacity(0.1))
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 30)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Graph Size")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 30)
                        .padding(.top, 8)

                    HStack(spacing: 10) {
                        ForEach(TemperatureGraphSize.allCases, id: \.self) { sizePreset in
                            Button {
                                temperatureGraphSizePreset = sizePreset
                            } label: {
                                Text(sizePreset.rawValue)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(temperatureGraphSizePreset == sizePreset ? .white : .blue)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(temperatureGraphSizePreset == sizePreset ? Color.blue : Color.blue.opacity(0.1))
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 30)
                }
            }

            Spacer()
        }
        .padding(.top, 10)
    }
}
