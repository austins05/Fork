import Foundation

class PinSyncService {
    static let shared = PinSyncService()
    
    private let baseURL = "https://rotorsync-web.vercel.app"
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Helper Methods
    
    private func getUserId() -> String? {
        struct UserData: Codable { let id: String }
        guard let data = UserDefaults.standard.data(forKey: "userData"),
              let user = try? JSONDecoder().decode(UserData.self, from: data) else {
            return nil
        }
        return user.id
    }
    
    private func makeRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> Data {
        var components = URLComponents(string: "\(baseURL)\(path)")
        components?.queryItems = queryItems
        
        guard let url = components?.url else {
            throw NSError(domain: "Invalid URL", code: -1)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let body = body {
            request.httpBody = body
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "Invalid response", code: -1)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("API Error (\(httpResponse.statusCode)): \(errorMessage)")
            throw NSError(domain: "API Error", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: errorMessage
            ])
        }
        
        return data
    }
    
    // MARK: - Pin API Calls
    
    /// Upload a pin to the server
    func uploadPin(
        name: String,
        latitude: Double,
        longitude: Double,
        iconName: String,
        groupId: String?,
        folderId: String?
    ) async throws -> APIPin {
        guard let userId = getUserId() else {
            throw NSError(domain: "User not logged in", code: -1)
        }
        
        let payload: [String: Any] = [
            "name": name,
            "latitude": latitude,
            "longitude": longitude,
            "iconName": iconName,
            "groupId": groupId as Any,
            "folderId": folderId as Any,
            "createdBy": userId
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let data = try await makeRequest(path: "/api/pin", method: "POST", body: jsonData)
        
        return try JSONDecoder().decode(APIPin.self, from: data)
    }
    
    /// Get all pins for a group
    func getGroupPins(groupId: String) async throws -> [APIPin] {
        let queryItems = [URLQueryItem(name: "groupId", value: groupId)]
        let data = try await makeRequest(path: "/api/pin", queryItems: queryItems)
        
        return try JSONDecoder().decode([APIPin].self, from: data)
    }
    
    /// Get pins updated since a timestamp (for syncing)
    func getPinsSince(groupId: String, since: Date) async throws -> [APIPin] {
        let formatter = ISO8601DateFormatter()
        let sinceString = formatter.string(from: since)
        
        let queryItems = [
            URLQueryItem(name: "groupId", value: groupId),
            URLQueryItem(name: "since", value: sinceString)
        ]
        let data = try await makeRequest(path: "/api/pin", queryItems: queryItems)
        
        return try JSONDecoder().decode([APIPin].self, from: data)
    }
    
    /// Update a pin on the server
    func updatePin(
        pinId: String,
        name: String?,
        latitude: Double?,
        longitude: Double?,
        iconName: String?,
        groupId: String?,
        folderId: String?
    ) async throws -> APIPin {
        var payload: [String: Any] = ["pinId": pinId]
        
        if let name = name { payload["name"] = name }
        if let latitude = latitude { payload["latitude"] = latitude }
        if let longitude = longitude { payload["longitude"] = longitude }
        if let iconName = iconName { payload["iconName"] = iconName }
        if let groupId = groupId { payload["groupId"] = groupId }
        if let folderId = folderId { payload["folderId"] = folderId }
        
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let data = try await makeRequest(path: "/api/pin", method: "PATCH", body: jsonData)
        
        return try JSONDecoder().decode(APIPin.self, from: data)
    }
    
    /// Delete a pin from the server
    func deletePin(pinId: String) async throws {
        let queryItems = [URLQueryItem(name: "pinId", value: pinId)]
        _ = try await makeRequest(path: "/api/pin", method: "DELETE", queryItems: queryItems)
    }
    
    /// Move pin to a different folder/group
    func movePin(pinId: String, folderId: String?, groupId: String?) async throws -> APIPin {
        let payload: [String: Any?] = [
            "pinId": pinId,
            "folderId": folderId,
            "groupId": groupId
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 })
        let data = try await makeRequest(path: "/api/pin", method: "PUT", body: jsonData)
        
        return try JSONDecoder().decode(APIPin.self, from: data)
    }
    
    // MARK: - Group API Calls
    
    /// Get all groups user belongs to
    func getUserGroups() async throws -> [APIGroup] {
        guard let userId = getUserId() else {
            throw NSError(domain: "User not logged in", code: -1)
        }
        
        let queryItems = [URLQueryItem(name: "userId", value: userId)]
        let data = try await makeRequest(path: "/api/group", queryItems: queryItems)
        
        return try JSONDecoder().decode([APIGroup].self, from: data)
    }
    
    /// Create a new group
    func createGroup(name: String, description: String?) async throws -> APIGroup {
        guard let userId = getUserId() else {
            throw NSError(domain: "User not logged in", code: -1)
        }
        
        let payload: [String: Any] = [
            "name": name,
            "description": description as Any,
            "ownerId": userId
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let data = try await makeRequest(path: "/api/group", method: "POST", body: jsonData)
        
        return try JSONDecoder().decode(APIGroup.self, from: data)
    }
    
    /// Get all members of a group
    func getGroupMembers(groupId: String) async throws -> Data {
        let queryItems = [URLQueryItem(name: "groupId", value: groupId)]
        return try await makeRequest(path: "/api/group", queryItems: queryItems)
    }
    
    /// Add a member to a group
    func addMember(groupId: String, userId: String, role: String = "member") async throws {
        let payload: [String: Any] = [
            "groupId": groupId,
            "userId": userId,
            "role": role
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        _ = try await makeRequest(path: "/api/group/member", method: "POST", body: jsonData)
    }
    
    /// Remove a member from a group
    func removeMember(groupId: String, userId: String) async throws {
        let queryItems = [
            URLQueryItem(name: "groupId", value: groupId),
            URLQueryItem(name: "userId", value: userId)
        ]
        _ = try await makeRequest(path: "/api/group/member", method: "DELETE", queryItems: queryItems)
    }
    
    // MARK: - Folder API Calls
    
    /// Get all folders in a group
    func getGroupFolders(groupId: String) async throws -> [APIFolder] {
        let queryItems = [URLQueryItem(name: "groupId", value: groupId)]
        let data = try await makeRequest(path: "/api/folder", queryItems: queryItems)
        
        return try JSONDecoder().decode([APIFolder].self, from: data)
    }
    
    /// Create a new folder
    func createFolder(name: String, groupId: String?) async throws -> APIFolder {
        let payload: [String: Any] = [
            "name": name,
            "groupId": groupId as Any
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let data = try await makeRequest(path: "/api/folder", method: "POST", body: jsonData)
        
        return try JSONDecoder().decode(APIFolder.self, from: data)
    }
    
    /// Update a folder
    func updateFolder(folderId: String, name: String) async throws -> APIFolder {
        let payload: [String: Any] = [
            "folderId": folderId,
            "name": name
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let data = try await makeRequest(path: "/api/folder", method: "PATCH", body: jsonData)
        
        return try JSONDecoder().decode(APIFolder.self, from: data)
    }
    
    /// Delete a folder
    func deleteFolder(folderId: String) async throws {
        let queryItems = [URLQueryItem(name: "folderId", value: folderId)]
        _ = try await makeRequest(path: "/api/folder", method: "DELETE", queryItems: queryItems)
    }
    
    // MARK: - Device API Calls
    
    /// Fetch all devices
    func fetchDevices() async throws -> [Device] {
        guard let url = URL(string: "\(baseURL)/api/devices") else {
            throw NSError(domain: "Invalid URL", code: -1)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = KeychainService.getToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, _) = try await session.data(for: request)
        let decoded = try JSONDecoder().decode(DeviceResponse.self, from: data)
        
        guard decoded.success else {
            throw NSError(domain: decoded.error ?? "Unknown server error", code: -1)
        }
        
        return decoded.data
    }
}
