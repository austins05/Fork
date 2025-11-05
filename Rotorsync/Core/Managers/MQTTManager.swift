import Foundation
import CocoaMQTT
import CocoaMQTTWebSocket
import CoreLocation
import Combine

// MARK: - Notification
extension Notification.Name {
    static let deviceLocationUpdated = Notification.Name("deviceLocationUpdated")
}

// MARK: - MQTT Manager
@MainActor
final class MQTTManager: ObservableObject {
    static let shared = MQTTManager()
    
    @Published var isConnected = false
    
    private var mqtt: CocoaMQTT?
    private var userDevice: Device?
    private var allDevices: [Device] = []
    
    private init() {}
    
    // MARK: - Configuration
    
    private struct MQTTConfig {
        static let host = "ws.rotorsync.com"
        static let port: UInt16 = 443
        static let username = "app"
        static let password = "testapp!"
        static let keepAlive: UInt16 = 60
    }
    
    // MARK: - Start MQTT
    
    func start(with devices: [Device], userDevice: Device?) {
        self.allDevices = devices
        self.userDevice = userDevice
        
        setupMQTT()
        connect()
        subscribeToOtherDevices()
    }
    
    private func setupMQTT() {
        let clientID = "RotorSync-" + UUID().uuidString
        let websocket = CocoaMQTTWebSocket(uri: "/mqtt")
        websocket.enableSSL = true
        
        mqtt = CocoaMQTT(
            clientID: clientID,
            host: MQTTConfig.host,
            port: MQTTConfig.port,
            socket: websocket
        )
        
        mqtt?.username = MQTTConfig.username
        mqtt?.password = MQTTConfig.password
        mqtt?.keepAlive = MQTTConfig.keepAlive
        mqtt?.autoReconnect = true
        mqtt?.allowUntrustCACertificate = true
        mqtt?.logLevel = .debug
        mqtt?.delegate = self
    }
    
    private func connect() {
        print("MQTT: Connecting to \(MQTTConfig.host):\(MQTTConfig.port)...")
        isConnected = false
        _ = mqtt?.connect()
    }
    
    private func subscribeToOtherDevices() {
        guard let userDevice = userDevice else {
            print("No user device found, subscribing to all device topics")
            subscribeToAllDevices()
            return
        }
        
        let topics = allDevices
            .filter { $0.id != userDevice.id && $0.mqttTopic != nil }
            .compactMap { $0.mqttTopic }
        
        for topic in topics {
            mqtt?.subscribe(topic, qos: .qos1)
            print("Subscribed to: \(topic)")
        }
    }
    
    private func subscribeToAllDevices() {
        let topics = allDevices
            .compactMap { $0.mqttTopic }
        
        for topic in topics {
            mqtt?.subscribe(topic, qos: .qos1)
            print("Subscribed to: \(topic)")
        }
    }
    
    // MARK: - Publish User Location
    
    func publishUserLocation(_ location: CLLocation) {
        guard let topic = userDevice?.mqttTopic else {
            print("No MQTT topic for user device")
            return
        }
        
        let payload: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "speed": location.speed,
            "altitude": location.altitude,
            "accuracy": location.horizontalAccuracy,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("Failed to encode location payload")
            return
        }
        
        mqtt?.publish(topic, withString: jsonString, qos: .qos1)
        print("Published location to \(topic)")
    }
    
    // MARK: - Handle Incoming Message
    
    private func handleMessage(_ message: CocoaMQTTMessage) {
        guard let jsonString = message.string,
              let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lat = json["latitude"] as? Double,
              let lng = json["longitude"] as? Double else {
            print("Failed to parse MQTT message")
            return
        }
        
        let topic = message.topic
        
        if let index = allDevices.firstIndex(where: { $0.mqttTopic == topic }) {
            var updated = allDevices[index]
            updated.latitude = lat
            updated.longitude = lng
            allDevices[index] = updated
            
            print("Updated device location: \(updated.displayName) at (\(lat), \(lng))")
            
            NotificationCenter.default.post(
                name: .deviceLocationUpdated,
                object: updated
            )
        }
    }
    
    // MARK: - Connection Management
    
    func disconnect() {
        print("MQTT: Disconnecting...")
        mqtt?.disconnect()
    }
    
    func reconnect() {
        print("MQTT: Reconnecting...")
        disconnect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.connect()
        }
    }
    
    // MARK: - Status
    
    var connectionStatus: String {
        isConnected ? "Connected" : "Disconnected"
    }
    
    var deviceCount: Int {
        allDevices.count
    }
    
    var subscribedTopicsCount: Int {
        allDevices.filter { $0.mqttTopic != nil }.count
    }
}

// MARK: - CocoaMQTTDelegate
extension MQTTManager: CocoaMQTTDelegate {
    
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        print("MQTT: Connected with ack: \(ack)")
        isConnected = true
        subscribeToOtherDevices()
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        handleMessage(message)
    }
    
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        if let error = err {
            print("MQTT: Disconnected with error: \(error.localizedDescription)")
        } else {
            print("MQTT: Disconnected")
        }
        isConnected = false
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
    
    // MARK: - Required Delegate Methods
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        // Optional: Track published messages
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
        // Optional: Confirm message delivery
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        if !failed.isEmpty {
            print("Failed to subscribe to topics: \(failed)")
        }
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
        print("Unsubscribed from topics: \(topics)")
    }
    
    func mqttDidPing(_ mqtt: CocoaMQTT) {
        // Optional: Track ping
    }
    
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
        // Optional: Track pong
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
    
    func mqttUrlSession(_ mqtt: CocoaMQTT, didReceiveTrust trust: SecTrust, didReceiveChallenge challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
