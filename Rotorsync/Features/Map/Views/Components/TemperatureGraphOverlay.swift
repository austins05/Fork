import SwiftUI

struct TemperatureGraphOverlay: View {
    @ObservedObject var temperatureService = TemperatureService.shared
    @Binding var size: CGSize
    @Binding var isVisible: Bool
    @Binding var presetPosition: TemperatureGraphPosition
    @Binding var graphScale: CGFloat
    @State private var position: CGPoint = CGPoint(x: 150, y: 220)
    @State private var isDragging = false

    private let baseSize: CGSize = CGSize(width: 250, height: 150)
    private let minSize: CGSize = CGSize(width: 175, height: 105)
    private let maxSize: CGSize = CGSize(width: 375, height: 225)

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
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.85))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let newX = position.x + value.translation.width
                            let newY = position.y + value.translation.height

                            // Constrain position to keep graph away from edges
                            let minY: CGFloat = 100  // Keep away from status bar at top
                            let constrainedY = max(minY, newY)

                            position = CGPoint(x: newX, y: constrainedY)
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
            )
            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 0)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
            .overlay(
                // Resize handle (bottom right corner)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(6)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(6)
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
            .onChange(of: presetPosition) { newPosition in
                // Animate to new preset position when user changes it in settings
                withAnimation(.easeInOut(duration: 0.3)) {
                    position = newPosition.coordinates
                }
            }
            .onChange(of: graphScale) { newScale in
                // Animate to new size when user changes scale in settings
                withAnimation(.easeInOut(duration: 0.3)) {
                    let newWidth = max(minSize.width, min(maxSize.width, baseSize.width * newScale))
                    let newHeight = max(minSize.height, min(maxSize.height, baseSize.height * newScale))
                    size = CGSize(width: newWidth, height: newHeight)
                }
            }
            .onAppear {
                // Set initial position and size
                position = presetPosition.coordinates
                let initialWidth = max(minSize.width, min(maxSize.width, baseSize.width * graphScale))
                let initialHeight = max(minSize.height, min(maxSize.height, baseSize.height * graphScale))
                size = CGSize(width: initialWidth, height: initialHeight)
            }
        }
    }

    private var graphContent: some View {
        VStack(spacing: 6) {
            // Legend
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(Color(red: 0.2, green: 0.5, blue: 1.0))
                        .frame(width: 10, height: 2)
                    Text("EGT")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }

                HStack(spacing: 4) {
                    Rectangle()
                        .fill(Color(red: 0.2, green: 0.8, blue: 0.3))
                        .frame(width: 10, height: 2)
                    Text("CHT")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                // Max values
                VStack(alignment: .trailing, spacing: 1) {
                    if let maxEGT = temperatureService.egtReadings.map(\.temperature).max() {
                        Text("EGT: \(Int(maxEGT))°F")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.2, green: 0.5, blue: 1.0))
                    }
                    if let maxCHT = temperatureService.chtReadings.map(\.temperature).max() {
                        Text("CHT: \(Int(maxCHT))°F")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.3))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            // Simple bar chart showing current readings
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(1...6, id: \.self) { cylinder in
                        compactCylinderBars(
                            cylinderNumber: cylinder,
                            chtReading: temperatureService.chtReadings.first(where: { $0.channel == cylinder }),
                            egtReading: temperatureService.egtReadings.first(where: { $0.channel == cylinder })
                        )
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(height: size.height - 60) // Adjust based on header and legend
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
        VStack(spacing: 3) {
            // EGT temperature value (at top)
            if let egt = egtReading {
                Text("\(Int(egt.temperature))")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(red: 0.2, green: 0.5, blue: 1.0))
            } else {
                Text("--")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(red: 0.2, green: 0.5, blue: 1.0).opacity(0.3))
            }

            // Cylinder number
            Text("\(cylinderNumber)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.6))

            // Bars
            HStack(spacing: 3) {
                // CHT bar
                compactBar(
                    temperature: chtReading?.temperature ?? 0,
                    color: Color(red: 0.2, green: 0.8, blue: 0.3),
                    minScale: 250,
                    maxScale: 500,
                    width: (size.width - 120) / 15 // Responsive width
                )

                // EGT bar
                compactBar(
                    temperature: egtReading?.temperature ?? 0,
                    color: Color(red: 0.2, green: 0.5, blue: 1.0),
                    minScale: 1200,
                    maxScale: 1700,
                    width: (size.width - 120) / 15 // Responsive width
                )
            }

            // CHT temperature value (at bottom)
            if let cht = chtReading {
                Text("\(Int(cht.temperature))")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.3))
            } else {
                Text("--")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.3).opacity(0.3))
            }
        }
    }

    private func compactBar(temperature: Double, color: Color, minScale: Double, maxScale: Double, width: CGFloat) -> some View {
        let height: CGFloat = size.height - 90 // Available height for bars (reduced from 100)
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
