import SwiftUI

struct TemperatureGraphOverlay: View {
    @ObservedObject var temperatureService = TemperatureService.shared
    @Binding var size: CGSize
    @Binding var isVisible: Bool
    @GestureState private var dragOffset = CGSize.zero
    @State private var position: CGPoint = CGPoint(x: 200, y: 350) // Default position

    private let minSize: CGSize = CGSize(width: 200, height: 120)
    private let maxSize: CGSize = CGSize(width: 400, height: 300)

    var body: some View {
        if isVisible {
            VStack(spacing: 0) {
                // Header with drag handle
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))

                    Text("ENGINE TEMPS")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                        .tracking(0.5)

                    Spacer()

                    if temperatureService.isConnected {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                    } else {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.85))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            position = CGPoint(
                                x: position.x + value.translation.width,
                                y: position.y + value.translation.height
                            )
                        }
                )

                // Graph content
                if temperatureService.isConnected || !temperatureService.chtReadings.isEmpty {
                    graphContent
                } else {
                    placeholderContent
                }
            }
            .frame(width: size.width, height: size.height)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.75))
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
            .overlay(
                // Resize handle (bottom right corner)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(8)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(8)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newWidth = max(minSize.width, min(maxSize.width, size.width + value.translation.width))
                                let newHeight = max(minSize.height, min(maxSize.height, size.height + value.translation.height))
                                size = CGSize(width: newWidth, height: newHeight)
                            }
                    )
            )
            .position(position)
        }
    }

    private var graphContent: some View {
        VStack(spacing: 8) {
            // Legend
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(Color(red: 1.0, green: 0.3, blue: 0.3))
                        .frame(width: 12, height: 3)
                    Text("EGT")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }

                HStack(spacing: 4) {
                    Rectangle()
                        .fill(Color(red: 1.0, green: 0.6, blue: 0.2))
                        .frame(width: 12, height: 3)
                    Text("CHT")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                // Max values
                VStack(alignment: .trailing, spacing: 2) {
                    if let maxEGT = temperatureService.egtReadings.map(\.temperature).max() {
                        Text("EGT: \(Int(maxEGT))°F")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 1.0, green: 0.3, blue: 0.3))
                    }
                    if let maxCHT = temperatureService.chtReadings.map(\.temperature).max() {
                        Text("CHT: \(Int(maxCHT))°F")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.2))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Simple bar chart showing current readings
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(1...6, id: \.self) { cylinder in
                        compactCylinderBars(
                            cylinderNumber: cylinder,
                            chtReading: temperatureService.chtReadings.first(where: { $0.channel == cylinder }),
                            egtReading: temperatureService.egtReadings.first(where: { $0.channel == cylinder })
                        )
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: size.height - 70) // Adjust based on header and legend
        }
    }

    private var placeholderContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.white.opacity(0.3))

            Text("Awaiting Data")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func compactCylinderBars(cylinderNumber: Int, chtReading: TemperatureReading?, egtReading: TemperatureReading?) -> some View {
        VStack(spacing: 4) {
            // Cylinder number
            Text("\(cylinderNumber)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.6))

            // Bars
            HStack(spacing: 3) {
                // CHT bar
                compactBar(
                    temperature: chtReading?.temperature ?? 0,
                    color: Color(red: 1.0, green: 0.6, blue: 0.2),
                    minScale: 250,
                    maxScale: 500,
                    width: (size.width - 120) / 15 // Responsive width
                )

                // EGT bar
                compactBar(
                    temperature: egtReading?.temperature ?? 0,
                    color: Color(red: 1.0, green: 0.3, blue: 0.3),
                    minScale: 1200,
                    maxScale: 1700,
                    width: (size.width - 120) / 15 // Responsive width
                )
            }

            // Temperature values
            VStack(spacing: 1) {
                if let cht = chtReading {
                    Text("\(Int(cht.temperature))")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.2))
                }
                if let egt = egtReading {
                    Text("\(Int(egt.temperature))")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(red: 1.0, green: 0.3, blue: 0.3))
                }
            }
        }
    }

    private func compactBar(temperature: Double, color: Color, minScale: Double, maxScale: Double, width: CGFloat) -> some View {
        let height: CGFloat = size.height - 100 // Available height for bars
        let normalized = (temperature - minScale) / (maxScale - minScale)
        let clamped = min(max(normalized, 0), 1)
        let barHeight = CGFloat(clamped) * height

        return VStack {
            Spacer()
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [color.opacity(0.8), color]),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: width, height: barHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(color.opacity(0.5), lineWidth: 0.5)
                )
        }
        .frame(height: height)
    }
}
