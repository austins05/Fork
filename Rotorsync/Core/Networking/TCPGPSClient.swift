//
//  TCPGPSClient.swift
//  Rotorsync
//
//  Created for TCP GPS support
//

import Foundation
import Network
import CoreLocation
import Combine

/// Manages TCP connection to external GPS source and parses NMEA data
class TCPGPSClient: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentLocation: CLLocation?
    @Published var isConnected = false
    @Published var connectionError: String?
    
    // MARK: - Private Properties
    
    private var connection: NWConnection?
    private let parser = NMEAParser()
    private var receiveBuffer = ""
    private let queue = DispatchQueue(label: "com.rotorsync.tcpgps", qos: .userInitiated)
    
    // Connection settings
    private var currentHost: String?
    private var currentPort: UInt16?
    
    // MARK: - Connection Management
    
    /// Connect to TCP GPS server
    /// - Parameters:
    ///   - host: Server hostname or IP address
    ///   - port: Server port number
    func connect(host: String, port: UInt16) {
        // Disconnect existing connection if any
        disconnect()
        
        currentHost = host
        currentPort = port
        
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        
        connection = NWConnection(to: endpoint, using: .tcp)
        
        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                self?.handleStateChange(state)
            }
        }
        
        connection?.start(queue: queue)
    }
    
    /// Disconnect from TCP GPS server
    func disconnect() {
        connection?.cancel()
        connection = nil
        receiveBuffer = ""
        
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionError = nil
        }
    }
    
    /// Reconnect to the last server
    func reconnect() {
        guard let host = currentHost, let port = currentPort else { return }
        connect(host: host, port: port)
    }
    
    // MARK: - Private Methods
    
    private func handleStateChange(_ state: NWConnection.State) {
        switch state {
        case .ready:
            isConnected = true
            connectionError = nil
            print("[TCPGPSClient] Connected to TCP GPS")
            receiveData()
            
        case .waiting(let error):
            isConnected = false
            connectionError = "Waiting: \(error.localizedDescription)"
            print("[TCPGPSClient] Waiting: \(error)")
            
        case .failed(let error):
            isConnected = false
            connectionError = "Failed: \(error.localizedDescription)"
            print("[TCPGPSClient] Failed: \(error)")
            
            // Attempt reconnection after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                if let self = self, !self.isConnected {
                    print("[TCPGPSClient] Attempting reconnection...")
                    self.reconnect()
                }
            }
            
        case .cancelled:
            isConnected = false
            connectionError = nil
            print("[TCPGPSClient] Connection cancelled")
            
        default:
            break
        }
    }
    
    private func receiveData() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.connectionError = "Receive error: \(error.localizedDescription)"
                }
                print("[TCPGPSClient] Receive error: \(error)")
                return
            }
            
            if let data = data, !data.isEmpty {
                if let string = String(data: data, encoding: .utf8) {
                    self.receiveBuffer += string
                    self.processBuffer()
                }
            }
            
            if isComplete {
                print("[TCPGPSClient] Connection completed")
                self.disconnect()
            } else {
                self.receiveData()
            }
        }
    }
    
    private func processBuffer() {
        let lines = receiveBuffer.components(separatedBy: .newlines)
        receiveBuffer = lines.last ?? ""
        
        for line in lines.dropLast() {
            // NMEA sentences start with $
            if line.starts(with: "$") {
                print("[TCPGPSClient] Received NMEA: \(line)")
                if let gpsData = parser.parse(line) {
                    let newLocation = gpsData.toCLLocation()
                    print("[TCPGPSClient] ✅ Parsed location: lat=\(newLocation.coordinate.latitude), lon=\(newLocation.coordinate.longitude), speed=\(newLocation.speed)m/s (\(newLocation.speed * 2.23694)mph), course=\(newLocation.course)°")
                    
                    DispatchQueue.main.async {
                        // Merge with existing location to preserve speed/course from GPRMC when GPGGA arrives
                        if let existing = self.currentLocation {
                            // Keep speed and course from GPRMC if new data (GPGGA) doesn't have them
                            let speed = (newLocation.speed > 0 || newLocation.speed == 0 && line.contains("GPRMC")) ? newLocation.speed : existing.speed
                            let course = (newLocation.course >= 0) ? newLocation.course : existing.course
                            
                            let mergedLocation = CLLocation(
                                coordinate: newLocation.coordinate,
                                altitude: newLocation.altitude,
                                horizontalAccuracy: newLocation.horizontalAccuracy,
                                verticalAccuracy: newLocation.verticalAccuracy,
                                course: course,
                                speed: speed,
                                timestamp: newLocation.timestamp
                            )
                            self.currentLocation = mergedLocation
                            print("[TCPGPSClient] 🔀 Merged location: speed=\(speed)m/s, course=\(course)°")
                        } else {
                            self.currentLocation = newLocation
                            print("[TCPGPSClient] 📍 Initial location set")
                        }
                    }
                } else {
                    print("[TCPGPSClient] ❌ Failed to parse: \(line)")
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    var statusString: String {
        if isConnected {
            return "Connected"
        } else if let error = connectionError {
            return error
        } else {
            return "Disconnected"
        }
    }
}
