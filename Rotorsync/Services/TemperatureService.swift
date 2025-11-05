//
//  TemperatureService.swift
//  Temperature monitoring service using PeerTalk
//

import Foundation
import Combine

// Frame types for communication
enum TemperatureFrameType: UInt32 {
    case temperatureData = 100
    case ping = 102
    case pong = 103
}

// Temperature reading model
struct TemperatureReading: Codable, Identifiable {
    let id = UUID()
    let type: String  // "CHT" or "EGT"
    let channel: Int  // 1-6
    let temperature: Double
    let unit: String // "C" or "F"
    let timestamp: Date
    
    enum CodingKeys: String, CodingKey {
        case type, channel, temperature, unit, timestamp
    }
}

// Temperature data payload from Pi
struct TemperatureDataPayload: Codable {
    let cht: [Double]  // 6 CHT readings
    let egt: [Double]  // 6 EGT readings
    let timestamp: Double
    let unit: String
}

class TemperatureService: NSObject, ObservableObject {
    static let shared = TemperatureService()
    
    // Published properties for SwiftUI
    @Published var isConnected = false
    @Published var chtReadings: [TemperatureReading] = []
    @Published var egtReadings: [TemperatureReading] = []
    @Published var lastUpdateTime: Date?
    @Published var connectionStatus: String = "Waiting for Pi connection..."
    
    private var serverChannel: PTChannel?
    private var peerChannel: PTChannel?
    private let port: in_port_t = 2345
    private var frameCount = 0
    
    private override init() {
        super.init()
    }
    
    func startListening() {
        print("🔌 Starting PeerTalk server on port \(port)...")
        
        // Create channel
        let channel = PTChannel(protocol: nil, delegate: self)
        
        // Listen on localhost
        channel.listen(on: port, IPv4Address: INADDR_LOOPBACK) { [weak self] error in
            if let error = error {
                print("❌ Failed to listen: \(error)")
                DispatchQueue.main.async {
                    self?.connectionStatus = "Failed to start: \(error.localizedDescription)"
                }
            } else {
                print("✅ Listening on 127.0.0.1:\(self?.port ?? 0)")
                DispatchQueue.main.async {
                    self?.serverChannel = channel
                    self?.connectionStatus = "Listening for Pi connection..."
                }
            }
        }
    }
    
    func stopListening() {
        serverChannel?.cancel()
        peerChannel?.cancel()
        serverChannel = nil
        peerChannel = nil
        isConnected = false
        connectionStatus = "Disconnected"
    }
    
    private func handleTemperatureData(_ data: Data) {
        print("🔍 Parsing temperature data (\(data.count) bytes)...")
        print("📦 JSON: \(String(data: data, encoding: .utf8) ?? "invalid UTF-8")")
        
        do {
            let decoder = JSONDecoder()
            let payload = try decoder.decode(TemperatureDataPayload.self, from: data)
            
            let timestamp = Date(timeIntervalSince1970: payload.timestamp)
            
            // Convert CHT readings
            var newChtReadings: [TemperatureReading] = []
            for (index, temp) in payload.cht.enumerated() {
                let reading = TemperatureReading(
                    type: "CHT",
                    channel: index + 1,
                    temperature: temp,
                    unit: payload.unit,
                    timestamp: timestamp
                )
                newChtReadings.append(reading)
            }
            
            // Convert EGT readings
            var newEgtReadings: [TemperatureReading] = []
            for (index, temp) in payload.egt.enumerated() {
                let reading = TemperatureReading(
                    type: "EGT",
                    channel: index + 1,
                    temperature: temp,
                    unit: payload.unit,
                    timestamp: timestamp
                )
                newEgtReadings.append(reading)
            }
            
            // Update on main thread
            DispatchQueue.main.async { [weak self] in
                self?.chtReadings = newChtReadings
                self?.egtReadings = newEgtReadings
                self?.lastUpdateTime = timestamp
            }
            
            print("✅ Successfully parsed - CHT: \(payload.cht.count), EGT: \(payload.egt.count)")
            
        } catch {
            print("❌ JSON decode failed: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("   Missing key: \(key.stringValue), context: \(context.debugDescription)")
                case .typeMismatch(let type, let context):
                    print("   Type mismatch: \(type), context: \(context.debugDescription)")
                case .valueNotFound(let type, let context):
                    print("   Value not found: \(type), context: \(context.debugDescription)")
                case .dataCorrupted(let context):
                    print("   Data corrupted: \(context.debugDescription)")
                @unknown default:
                    print("   Unknown decoding error")
                }
            }
        }
    }
}

// MARK: - PTChannelDelegate
extension TemperatureService: PTChannelDelegate {
    
    func channel(_ channel: PTChannel, didRecieveFrame type: UInt32, tag: UInt32, payload: Data?) {
        frameCount += 1
        print("📨 Frame #\(frameCount) received - type: \(type), tag: \(tag), payload size: \(payload?.count ?? 0) bytes")
        
        guard let frameType = TemperatureFrameType(rawValue: type) else {
            print("⚠️ Unknown frame type: \(type)")
            return
        }
        
        print("   Frame type: \(frameType)")
        
        switch frameType {
        case .temperatureData:
            if let payload = payload {
                handleTemperatureData(payload)
            } else {
                print("⚠️ Temperature frame has nil payload")
            }
            
        case .ping:
            print("🏓 Received ping, sending pong...")
            peerChannel?.sendFrame(type: TemperatureFrameType.pong.rawValue, tag: 0, payload: nil, callback: nil)
            
        case .pong:
            print("🏓 Received pong")
        }
    }
    
    func channel(_ channel: PTChannel, shouldAcceptFrame type: UInt32, tag: UInt32, payloadSize: UInt32) -> Bool {
        let serverCh = channel == serverChannel
        let peerCh = channel == peerChannel
        let noPeer = peerChannel == nil
        
        print("🔍 shouldAcceptFrame - type: \(type), tag: \(tag), size: \(payloadSize)")
        print("   channel == serverChannel: \(serverCh)")
        print("   channel == peerChannel: \(peerCh)")
        print("   peerChannel == nil: \(noPeer)")
        
        // Accept frames from peer channel, or if peer channel not set yet
        guard channel == peerChannel || peerChannel == nil else {
            print("   ❌ REJECTED: Channel mismatch")
            return false
        }

        if let frameType = TemperatureFrameType(rawValue: type) {
            let shouldAccept = frameType == .temperatureData || frameType == .ping
            print("   Frame type: \(frameType), accepting: \(shouldAccept)")
            return shouldAccept
        }

        print("   ❌ REJECTED: Unknown frame type")
        return false
    }
    
    func channel(_ channel: PTChannel, didAcceptConnection otherChannel: PTChannel, from address: PTAddress) {
        print("🎉 didAcceptConnection called")
        print("   From address: \(address)")
        print("   Old peerChannel: \(peerChannel != nil ? "exists" : "nil")")
        print("   New peerChannel being set...")
        
        // Disconnect existing peer if any
        if let oldPeer = peerChannel {
            print("   Canceling old peer connection...")
            oldPeer.cancel()
        }
        
        peerChannel = otherChannel
        peerChannel?.userInfo = address
        frameCount = 0
        
        print("✅ Peer channel set, ready to receive frames")
        
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = true
            self?.connectionStatus = "Connected to Pi"
        }
    }
    
    func channelDidEnd(_ channel: PTChannel, error: Error?) {
        print("⚠️ channelDidEnd called")
        print("   channel == serverChannel: \(channel == serverChannel)")
        print("   channel == peerChannel: \(channel == peerChannel)")
        print("   Total frames received: \(frameCount)")
        
        if let error = error {
            let nsError = error as NSError
            print("❌ Channel ended with error:")
            print("   Domain: \(nsError.domain)")
            print("   Code: \(nsError.code)")
            print("   Description: \(nsError.localizedDescription)")
            print("   User info: \(nsError.userInfo)")
            
            DispatchQueue.main.async { [weak self] in
                self?.connectionStatus = "Error: \(nsError.localizedDescription) (code \(nsError.code))"
            }
        } else {
            print("🔌 Channel ended normally (no error)")
            DispatchQueue.main.async { [weak self] in
                self?.connectionStatus = "Pi disconnected cleanly"
            }
        }
        
        if channel == peerChannel {
            print("   Clearing peerChannel reference")
            peerChannel = nil
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
        }
    }
}
