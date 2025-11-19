import Foundation

class RemoteLogger {
    static let shared = RemoteLogger()
    private let serverURL = "http://192.168.68.187:8080/log"
    private let queue = DispatchQueue(label: "com.rotorsync.remotelogger", qos: .background)
    private var consecutiveFailures = 0
    private let maxConsecutiveFailures = 10  // Only warn after 10 failures in a row
    private var lastWarningTime: Date?

    private init() {
        // Test connection on init (but don't disable if it fails)
        testConnection()
    }

    func log(_ message: String) {
        // Always print locally
        print(message)

        // Always try remote (don't give up permanently)
        queue.async { [weak self] in
            self?.sendLog(message)
        }
    }

    private func testConnection() {
        queue.async { [weak self] in
            guard let self = self,
                  let url = URL(string: self.serverURL) else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 1.0

            let json: [String: Any] = ["message": "🟢 RemoteLogger initialized"]
            guard let jsonData = try? JSONSerialization.data(withJSONObject: json) else { return }
            request.httpBody = jsonData

            let semaphore = DispatchSemaphore(value: 0)
            var success = false

            URLSession.shared.dataTask(with: request) { _, response, error in
                if error == nil, (response as? HTTPURLResponse)?.statusCode == 200 {
                    success = true
                }
                semaphore.signal()
            }.resume()

            _ = semaphore.wait(timeout: .now() + 2.0)

            if !success {
                print("⚠️ [RemoteLogger] Failed to connect to log server - will keep trying")
            } else {
                print("✅ [RemoteLogger] Connected to log server at \(self.serverURL)")
            }
        }
    }

    private func sendLog(_ message: String) {
        guard let url = URL(string: serverURL) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 2.0  // Increased timeout for reliability

        let json: [String: Any] = ["message": message]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: json) else { return }

        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            guard let self = self else { return }

            if error != nil || (response as? HTTPURLResponse)?.statusCode != 200 {
                // Track consecutive failures but NEVER permanently disable
                self.consecutiveFailures += 1

                // Only warn occasionally to avoid log spam
                let now = Date()
                let shouldWarn = self.lastWarningTime == nil ||
                                now.timeIntervalSince(self.lastWarningTime!) > 30.0

                if self.consecutiveFailures >= self.maxConsecutiveFailures && shouldWarn {
                    print("⚠️ [RemoteLogger] \(self.consecutiveFailures) consecutive failures - network may be unstable (still trying)")
                    self.lastWarningTime = now
                }
            } else {
                // Success - reset failure count
                if self.consecutiveFailures > 0 {
                    print("✅ [RemoteLogger] Reconnected after \(self.consecutiveFailures) failures")
                    self.consecutiveFailures = 0
                }
            }
        }.resume()
    }
}
