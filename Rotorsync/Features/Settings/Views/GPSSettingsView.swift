//
//  GPSSettingsView.swift
//  Rotorsync
//
//  Created for TCP GPS configuration
//

import SwiftUI
import CoreLocation

struct GPSSettingsView: View {
    @StateObject private var locationManager = LocationManager.shared
    @State private var settings = GPSSettings.load()
    @State private var showingTestResults = false
    @State private var testResultMessage = ""
    
    var body: some View {
        Form {
            // Current GPS Source Section
            Section {
                HStack {
                    Text("Current Source")
                    Spacer()
                    Text(locationManager.gpsSource == .tcp ? "TCP GPS" : "Internal GPS")
                        .foregroundColor(.secondary)
                }
                
                if let location = locationManager.userLocation {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Latitude:")
                            Spacer()
                            Text(String(format: "%.6f", location.coordinate.latitude))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Longitude:")
                            Spacer()
                            Text(String(format: "%.6f", location.coordinate.longitude))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Altitude:")
                            Spacer()
                            Text(locationManager.altitudeString)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Speed:")
                            Spacer()
                            Text(locationManager.speedString)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Accuracy:")
                            Spacer()
                            Text(locationManager.accuracyString)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Current Location Data")
            }
            
            // TCP GPS Configuration Section
            Section {
                Toggle("Enable TCP GPS", isOn: $settings.tcpEnabled)
                    .onChange(of: settings.tcpEnabled) { oldValue, newValue in
                        saveAndApplySettings()
                    }
                
                if settings.tcpEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server Address")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("192.168.1.100", text: $settings.tcpHost)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Port")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("10110", value: $settings.tcpPort, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.numberPad)
                    }
                    
                    Button(action: saveAndApplySettings) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Apply Settings")
                        }
                    }
                    .buttonStyle(.borderless)
                    
                    // Connection Status
                    if locationManager.gpsSource == .tcp {
                        HStack {
                            Circle()
                                .fill(locationManager.tcpGPSClient.isConnected ? Color.green : Color.red)
                                .frame(width: 10, height: 10)
                            Text(locationManager.tcpGPSClient.statusString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("TCP GPS Configuration")
            } footer: {
                Text("Enable TCP GPS to receive location data from an external GPS source over WiFi. When enabled, the internal GPS will be disabled to save battery.")
            }
            
            // Information Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(
                        icon: "antenna.radiowaves.left.and.right",
                        title: "NMEA Support",
                        description: "Supports GPRMC and GPGGA sentence formats"
                    )
                    
                    Divider()
                    
                    InfoRow(
                        icon: "network",
                        title: "Network Protocol",
                        description: "TCP connection over WiFi"
                    )
                    
                    Divider()
                    
                    InfoRow(
                        icon: "bolt.fill",
                        title: "Battery Savings",
                        description: "Internal GPS disabled when using TCP"
                    )
                }
            } header: {
                Text("About TCP GPS")
            }
        }
        .navigationTitle("GPS Settings")
        .navigationBarTitleDisplayMode(.large)
        .alert("Connection Test", isPresented: $showingTestResults) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(testResultMessage)
        }
        .onAppear {
            settings = GPSSettings.load()
        }
    }
    
    // MARK: - Helper Methods
    
    private func saveAndApplySettings() {
        locationManager.updateGPSSettings(settings)
    }
}

// MARK: - Supporting Views

struct InfoRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview

struct GPSSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            GPSSettingsView()
        }
    }
}
