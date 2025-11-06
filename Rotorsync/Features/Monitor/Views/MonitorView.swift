//
//  MonitorView.swift
//  Rotorsync - Professional Engine Monitor
//

import SwiftUI

struct MonitorView: View {
    @StateObject private var tempService = TemperatureService.shared
    @Environment(\.colorScheme) var colorScheme

    // Adaptive colors based on system appearance
    var backgroundColor: LinearGradient {
        colorScheme == .dark ?
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.05, green: 0.05, blue: 0.08),
                Color(red: 0.08, green: 0.08, blue: 0.12)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ) :
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.95, green: 0.95, blue: 0.97),
                Color(red: 0.92, green: 0.92, blue: 0.95)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var primaryTextColor: Color {
        colorScheme == .dark ? .white : Color(red: 0.1, green: 0.1, blue: 0.15)
    }

    var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.85) : Color(red: 0.2, green: 0.2, blue: 0.25)
    }

    var cardBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.03) : Color.white.opacity(0.7)
    }

    var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)
    }

    var body: some View {
        ZStack {
            // Adaptive background
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Professional header
                professionalHeader
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                // Minimized connection error banner (only shows when disconnected)
                if !tempService.isConnected {
                    connectionErrorBanner
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Always show content (with last known data when disconnected)
                ScrollView {
                    VStack(spacing: 32) {
                        // Stats overview
                        statsOverview
                            .padding(.horizontal, 24)
                            .padding(.top, 24)

                        // Single unified engine data display
                        engineDataDisplay
                            .padding(.horizontal, 24)
                            .padding(.bottom, 32)
                    }
                }
                .opacity(tempService.isConnected ? 1.0 : 0.6)

                Spacer()
            }
        }
        .statusBar(hidden: true)
        .onAppear {
            tempService.startListening()
        }
    }

    // MARK: - Connection Error Banner
    private var connectionErrorBanner: some View {
        HStack(spacing: 12) {
            // Warning icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Connection Lost")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(primaryTextColor)

                Text(tempService.connectionStatus)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(secondaryTextColor.opacity(0.8))
            }

            Spacer()

            // Reconnecting indicator
            ProgressView()
                .scaleEffect(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(colorScheme == .dark ? 0.15 : 0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Professional Header
    private var professionalHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            // Left side - Title
            VStack(alignment: .leading, spacing: 6) {
                Text("ENGINE MONITOR")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(primaryTextColor)
                    .tracking(1.2)

                HStack(spacing: 10) {
                    // Connection status indicator
                    ZStack {
                        Circle()
                            .fill(tempService.isConnected ? Color.green.opacity(0.3) : Color.orange.opacity(0.3))
                            .frame(width: 20, height: 20)
                            .blur(radius: 4)

                        Circle()
                            .fill(tempService.isConnected ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                    }

                    Text(tempService.connectionStatus)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                }
            }

            Spacer()

            // Right side - Live status
            if let lastUpdate = tempService.lastUpdateTime {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        if timeAgo(from: lastUpdate) == "LIVE" {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                        }

                        Text(timeAgo(from: lastUpdate))
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundColor(timeAgo(from: lastUpdate) == "LIVE" ? Color.green : secondaryTextColor)
                    }

                    Text("DATA STREAM")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(secondaryTextColor.opacity(0.7))
                        .tracking(1)
                }
            }
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackgroundColor)
        )
    }

    // MARK: - Stats Overview
    private var statsOverview: some View {
        HStack(spacing: 16) {
            // EGT Max
            StatCard(
                title: "EGT MAX",
                value: tempService.egtReadings.map(\.temperature).max() ?? 0,
                unit: "°F",
                color: Color(red: 0.2, green: 0.5, blue: 1.0),
                threshold: 1550
            )

            // CHT Max
            StatCard(
                title: "CHT MAX",
                value: tempService.chtReadings.map(\.temperature).max() ?? 0,
                unit: "°F",
                color: Color(red: 0.2, green: 0.8, blue: 0.3),
                threshold: 420
            )

            // Cylinders
            StatCard(
                title: "CYLINDERS",
                value: 6,
                unit: "",
                color: Color.blue,
                threshold: 999
            )
        }
    }

    // MARK: - Engine Data Display
    private var engineDataDisplay: some View {
        VStack(spacing: 16) {
            // Section header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ENGINE DATA")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(primaryTextColor)

                    Text("CYLINDER HEAD & EXHAUST GAS TEMPERATURE")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(secondaryTextColor.opacity(0.7))
                        .tracking(1.5)
                }

                Spacer()
            }
            .padding(.horizontal, 20)

            // EGT Max Difference (at top)
            HStack {
                Spacer()
                VStack(spacing: 2) {
                    Text("EGT MAX DIFF")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(secondaryTextColor.opacity(0.6))
                        .tracking(0.8)

                    Text("\(Int(calculateMaxDifference(readings: tempService.egtReadings)))°F")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.2, green: 0.5, blue: 1.0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0.2, green: 0.5, blue: 1.0).opacity(colorScheme == .dark ? 0.08 : 0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color(red: 0.2, green: 0.5, blue: 1.0).opacity(0.3), lineWidth: 1)
                        )
                )
                Spacer()
            }
            .padding(.horizontal, 20)

            // Horizontal scrolling bars - all 6 cylinders with paired CHT/EGT
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(1...6, id: \.self) { cylinderNum in
                        ProfessionalBarPair(
                            cylinderNumber: cylinderNum,
                            chtReading: tempService.chtReadings.first(where: { $0.channel == cylinderNum }),
                            egtReading: tempService.egtReadings.first(where: { $0.channel == cylinderNum }),
                            primaryType: "ENGINE",
                            dangerThreshold: 0,
                            warningThreshold: 0,
                            minScale: 0,
                            maxScale: 1700
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }

            // CHT Max Difference (at bottom)
            HStack {
                Spacer()
                VStack(spacing: 2) {
                    Text("CHT MAX DIFF")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(secondaryTextColor.opacity(0.6))
                        .tracking(0.8)

                    Text("\(Int(calculateMaxDifference(readings: tempService.chtReadings)))°F")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.3))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0.2, green: 0.8, blue: 0.3).opacity(colorScheme == .dark ? 0.08 : 0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color(red: 0.2, green: 0.8, blue: 0.3).opacity(0.3), lineWidth: 1)
                        )
                )
                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(cardBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
                .shadow(color: borderColor.opacity(0.3), radius: 20, x: 0, y: 10)
        )
    }

    // MARK: - Helper
    private func timeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 2 {
            return "LIVE"
        } else if seconds < 60 {
            return "\(seconds)s"
        } else {
            return "\(seconds / 60)m"
        }
    }

    private func calculateMaxDifference(readings: [TemperatureReading]) -> Double {
        let temps = readings.map { $0.temperature }
        guard let max = temps.max(), let min = temps.min(), !temps.isEmpty else {
            return 0
        }
        return max - min
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let title: String
    let value: Double
    let unit: String
    let color: Color
    let threshold: Double
    @Environment(\.colorScheme) var colorScheme

    var isOverThreshold: Bool {
        value > threshold
    }

    var textColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.6)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(textColor)
                .tracking(1.2)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value == 6 ? "6" : String(Int(value)))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(isOverThreshold ? Color.red : color)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(textColor)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(colorScheme == .dark ? 0.08 : 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(color.opacity(colorScheme == .dark ? 0.2 : 0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Professional Bar Pair
struct ProfessionalBarPair: View {
    let cylinderNumber: Int
    let chtReading: TemperatureReading?
    let egtReading: TemperatureReading?
    let primaryType: String
    let dangerThreshold: Double
    let warningThreshold: Double
    let minScale: Double
    let maxScale: Double
    @Environment(\.colorScheme) var colorScheme

    var labelTextColor: Color {
        colorScheme == .dark ? .white : Color(red: 0.1, green: 0.1, blue: 0.15)
    }

    var labelBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.6)
    }

    var labelBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.15)
    }

    var body: some View {
        VStack(spacing: 6) {
            // EGT temperature value (at top)
            if let egt = egtReading {
                Text("\(Int(egt.temperature))")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.2, green: 0.5, blue: 1.0))
            } else {
                Text("---")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.2, green: 0.5, blue: 1.0).opacity(0.3))
            }

            // Cylinder number
            Text("\(cylinderNumber)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(labelTextColor)
                .frame(width: 70, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(labelBackgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(labelBorderColor, lineWidth: 1)
                        )
                )

            // Bar pair
            HStack(spacing: 8) {
                // CHT bar
                ProfessionalSingleBar(
                    reading: chtReading,
                    label: "C",
                    color: Color(red: 0.2, green: 0.8, blue: 0.3),
                    isPrimary: primaryType == "CHT",
                    dangerThreshold: 500,
                    warningThreshold: 420,
                    minScale: 250,
                    maxScale: 500
                )

                // EGT bar
                ProfessionalSingleBar(
                    reading: egtReading,
                    label: "E",
                    color: Color(red: 0.2, green: 0.5, blue: 1.0),
                    isPrimary: primaryType == "EGT",
                    dangerThreshold: 1650,
                    warningThreshold: 1550,
                    minScale: 1200,
                    maxScale: 1700
                )
            }

            // CHT temperature value (at bottom)
            if let cht = chtReading {
                Text("\(Int(cht.temperature))")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.3))
            } else {
                Text("---")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.3).opacity(0.3))
            }
        }
    }
}

// MARK: - Professional Single Bar
struct ProfessionalSingleBar: View {
    let reading: TemperatureReading?
    let label: String
    let color: Color
    let isPrimary: Bool
    let dangerThreshold: Double
    let warningThreshold: Double
    let minScale: Double
    let maxScale: Double
    @Environment(\.colorScheme) var colorScheme

    var temperature: Double {
        reading?.temperature ?? 0
    }

    var barColor: Color {
        if temperature >= dangerThreshold {
            return .red
        } else if temperature >= warningThreshold {
            return Color(red: 1.0, green: 0.7, blue: 0.0)
        } else {
            return color
        }
    }

    var noDataColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.3)
    }

    var barBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.05)
    }

    var barBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)
    }

    var labelColor: Color {
        colorScheme == .dark ? Color.white.opacity(isPrimary ? 0.7 : 0.4) : Color.black.opacity(isPrimary ? 0.7 : 0.4)
    }

    var body: some View {
        VStack(spacing: 6) {
            // Vertical bar
            ZStack(alignment: .bottom) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(barBackgroundColor)
                    .frame(width: isPrimary ? 34 : 26, height: 260)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(barBorderColor, lineWidth: 1)
                    )

                // Red danger threshold line
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: isPrimary ? 34 : 26, height: 2)
                    Spacer()
                        .frame(height: barHeight(for: dangerThreshold) - 1)
                }
                .frame(height: 260)

                // Temperature fill
                if let reading = reading {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: barColor.opacity(0.8), location: 0.0),
                                    .init(color: barColor, location: 0.5),
                                    .init(color: barColor.opacity(0.9), location: 1.0)
                                ]),
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: isPrimary ? 34 : 26, height: barHeight(for: temperature))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(barColor.opacity(0.5), lineWidth: 1.5)
                        )
                        .shadow(color: barColor.opacity(0.4), radius: 8, x: 0, y: 4)
                }
            }

            // Label at bottom
            Text(label)
                .font(.system(size: isPrimary ? 12 : 10, weight: .bold, design: .rounded))
                .foregroundColor(labelColor)
                .frame(height: 20)
        }
    }

    private func barHeight(for temp: Double) -> CGFloat {
        let normalized = (temp - minScale) / (maxScale - minScale)
        let clamped = min(max(normalized, 0), 1)
        return CGFloat(clamped * 260)
    }
}

#Preview {
    MonitorView()
}
