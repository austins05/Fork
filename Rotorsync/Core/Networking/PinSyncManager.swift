import Foundation

class PinSyncManager {
    static let shared = PinSyncManager()
    
    private let apiService = PinSyncService.shared
    private let coreDataService = CoreDataService()
    private var syncTimer: Timer?
    private var lastSyncTimestamp: Date?
    
    private init() {}
    
    // MARK: - Sync Methods
    
    /// Start automatic syncing every 30 seconds
    func startAutoSync(groupId: String) {
        stopAutoSync()
        
        // Initial sync
        Task {
            await syncPins(groupId: groupId)
        }
        
        // Set up timer for periodic sync
        syncTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task {
                await self?.syncPins(groupId: groupId)
            }
        }
    }
    
    /// Stop automatic syncing
    func stopAutoSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
    
    /// Sync pins with the server
    func syncPins(groupId: String) async {
        do {
            // Get pins from server since last sync
            let serverPins: [APIPin]
            if let lastSync = lastSyncTimestamp {
                serverPins = try await apiService.getPinsSince(groupId: groupId, since: lastSync)
            } else {
                serverPins = try await apiService.getGroupPins(groupId: groupId)
            }
            
            // Update local database with server pins
            await updateLocalPins(serverPins: serverPins)
            
            // Update last sync timestamp
            lastSyncTimestamp = Date()
            
            print("Sync completed: \(serverPins.count) pins synced")
        } catch {
            print("Sync failed: \(error.localizedDescription)")
        }
    }
    
    /// Upload a local pin to the server
    func uploadPinToServer(
        name: String,
        latitude: Double,
        longitude: Double,
        iconName: String,
        groupId: String?,
        folderId: String?
    ) async throws -> APIPin {
        return try await apiService.uploadPin(
            name: name,
            latitude: latitude,
            longitude: longitude,
            iconName: iconName,
            groupId: groupId,
            folderId: folderId
        )
    }
    
    /// Update local Core Data with server pins
    private func updateLocalPins(serverPins: [APIPin]) async {
        // TODO: Implement logic to update local Core Data
        // For each server pin:
        // 1. Check if pin exists locally by server ID
        // 2. If exists, update it
        // 3. If not exists, create it
        
        print("Updating local database with \(serverPins.count) pins from server")
    }
    
    /// Delete a pin from server and local database
    func deletePin(pinId: String, localPin: PinEntity) async throws {
        // Delete from server
        try await apiService.deletePin(pinId: pinId)
        
        // Delete from local database
        try await coreDataService.deletePin(localPin)
        
        print("✅ Pin deleted from both server and local database")
    }
    
    /// Update a pin on server and local database
    func updatePin(
        pinId: String,
        localPin: PinEntity,
        name: String?,
        latitude: Double?,
        longitude: Double?,
        iconName: String?
    ) async throws -> APIPin {
        // Update on server
        let updatedPin = try await apiService.updatePin(
            pinId: pinId,
            name: name,
            latitude: latitude,
            longitude: longitude,
            iconName: iconName,
            groupId: nil,
            folderId: nil
        )
        
        // Update local database
        try await coreDataService.updatePin(
            localPin,
            name: name,
            latitude: latitude,
            longitude: longitude,
            iconName: iconName
        )
        
        print("✅ Pin updated on both server and local database")
        return updatedPin
    }
}
