//
//  MonitorView.swift
//  Rotorsync - Garmin G1000 Style Engine Monitor
//

import SwiftUI

struct MonitorView: View {
    @StateObject private var tempService = TemperatureService.shared

    var body: some View {
        ZStack {
            // Black background
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top status bar
                headerView
                    .padding(.horizontal)
                    .padding(.top, 8)

                if tempService.isConnected {
                    VStack(spacing: 20) {
                        // Statistics bar (like Garmin)
                        statsBar
                            .padding(.horizontal)
                            .padding(.top, 20)

                        // Bar graph section
                        barGraphSection
                            .padding(.horizontal)
                    }
                } else {
                    waitingView
                }

                Spacer()
            }
        }
        .statusBar(hidden: true)
        .onAppear {
            tempService.startListening()
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("ENGINE")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                HStack(spacing: 8) {
                    Circle()
                        .fill(tempService.isConnected ? Color.green : Color.orange)
                        .frame(width: 12, height: 12)

                    Text(tempService.connectionStatus)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            }

            Spacer()

            if let lastUpdate = tempService.lastUpdateTime {
                Text(timeAgo(from: lastUpdate))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(timeAgo(from: lastUpdate) == "LIVE" ? Color.green : Color.white.opacity(0.6))
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Stats Bar (Garmin Style)
    private var statsBar: some View {
        HStack(spacing: 0) {
            // CHT
            StatDisplay(
                label: "CHT",
                value: tempService.chtReadings.map(\.temperature).max() ?? 0,
                unit: "°F",
                color: .green
            )

            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 1, height: 40)

            // EGT
            StatDisplay(
                label: "EGT",
                value: tempService.egtReadings.map(\.temperature).max() ?? 0,
                unit: "°F",
                color: .green
            )

            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 1, height: 40)

            // TIT (or AVG as placeholder)
            StatDisplay(
                label: "TIT",
                value: tempService.egtReadings.isEmpty ? 0 : tempService.egtReadings.map(\.temperature).reduce(0, +) / Double(tempService.egtReadings.count),
                unit: "°F",
                color: .green
            )
        }
        .frame(height: 70)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Bar Graph Section
    private var barGraphSection: some View {
        VStack(spacing: 12) {
            // Label on left
            HStack {
                Text("CHT")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
                Spacer()
            }

            // Horizontal bar graph - alternating CHT/EGT for each cylinder
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(1...6, id: \.self) { cylinderNum in
                        HStack(spacing: 4) {
                            // CHT bar
                            GarminBar(
                                cylinderNumber: cylinderNum,
                                reading: tempService.chtReadings.first(where: { $0.channel == cylinderNum }),
                                type: "CHT",
                                showCylinderLabel: true
                            )

                            // EGT bar
                            GarminBar(
                                cylinderNumber: cylinderNum,
                                reading: tempService.egtReadings.first(where: { $0.channel == cylinderNum }),
                                type: "EGT",
                                showCylinderLabel: false
                            )
                        }
                        .padding(.trailing, cylinderNum < 6 ? 16 : 0)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Waiting View
    private var waitingView: some View {
        VStack(spacing: 30) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 70))
                .foregroundColor(.white.opacity(0.3))

            VStack(spacing: 8) {
                Text("Waiting for Pi Connection")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))

                Text(tempService.connectionStatus)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Helper
    private func timeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 2 {
            return "LIVE"
        } else if seconds < 60 {
            return String(seconds) + "s"
        } else {
            return String(seconds / 60) + "m"
        }
    }
}

// MARK: - Stat Display (Top Bar)
struct StatDisplay: View {
    let label: String
    let value: Double
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label + unit)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))

            Text(String(Int(value)))
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Garmin Bar (Single CHT or EGT)
struct GarminBar: View {
    let cylinderNumber: Int
    let reading: TemperatureReading?
    let type: String  // "CHT" or "EGT"
    let showCylinderLabel: Bool  // Only show on CHT bar

    var temperature: Double {
        reading?.temperature ?? 0
    }

    var dangerThreshold: Double {
        type == "EGT" ? 1650 : 450
    }

    var warningThreshold: Double {
        type == "EGT" ? 1550 : 420
    }

    var minScale: Double {
        type == "EGT" ? 1200 : 250
    }

    var maxScale: Double {
        type == "EGT" ? 1700 : 500
    }

    var barColor: Color {
        if temperature >= dangerThreshold {
            return .red
        } else if temperature >= warningThreshold {
            return .yellow
        } else {
            return type == "EGT" ? .cyan : .green
        }
    }

    var secondaryColor: Color {
        if temperature >= dangerThreshold {
            return .orange
        } else if temperature >= warningThreshold {
            return .orange
        } else {
            return .green
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Temperature value
            if reading != nil {
                Text(String(Int(temperature)))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(barColor)
                    .frame(height: 22)
            } else {
                Text("---")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(height: 22)
            }

            // Vertical bar
            ZStack(alignment: .bottom) {
                // Background with zones
                VStack(spacing: 0) {
                    // Danger zone
                    Rectangle()
                        .fill(Color.red.opacity(0.2))
                        .frame(height: barHeight(for: maxScale) - barHeight(for: dangerThreshold))

                    // Warning zone
                    Rectangle()
                        .fill(Color.yellow.opacity(0.2))
                        .frame(height: barHeight(for: dangerThreshold) - barHeight(for: warningThreshold))

                    // Normal zone
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: barHeight(for: warningThreshold))
                }
                .frame(width: 32, height: 280)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 3))

                // Actual temperature bar (two-tone gradient)
                if let reading = reading {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [secondaryColor, barColor]),
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 32, height: barHeight(for: temperature))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(barColor, lineWidth: 1.5)
                        )
                }
            }
            .frame(width: 32, height: 280)

            // Cylinder number (only on CHT bar)
            if showCylinderLabel {
                ZStack {
                    // Highlight box
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.cyan.opacity(0.3))
                        .frame(width: 30, height: 22)

                    Text(String(cylinderNumber))
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .frame(height: 24)
            } else {
                // Empty space for EGT bar
                Color.clear
                    .frame(height: 24)
            }
        }
    }

    private func barHeight(for temp: Double) -> CGFloat {
        let normalized = (temp - minScale) / (maxScale - minScale)
        let clamped = min(max(normalized, 0), 1)
        return CGFloat(clamped * 280)
    }
}

#Preview {
    MonitorView()
}
