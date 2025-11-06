import SwiftUI

struct OverlaySettingsView: View {
    @Binding var overlayScale: CGFloat
    @Binding var shareLocation: Bool
    @Binding var showTemperatureGraph: Bool

    var body: some View {
        VStack(spacing: 25) {
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

            Spacer()
        }
        .padding(.top, 10)
    }
}
