import Foundation
import CoreData
import Combine

@MainActor
final class FileManagerViewModel: ObservableObject {
    @Published var folders: [FolderEntity] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let coreDataService: CoreDataService
    private var cancellables = Set<AnyCancellable>()
    
    init(coreDataService: CoreDataService = CoreDataService()) {
        self.coreDataService = coreDataService
        setupNotifications()
    }
    
    // MARK: - Setup
    
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .coreDataDidChange)
            .sink { [weak self] _ in
                Task {
                    await self?.loadFolders()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Folder Operations
    
    func loadFolders() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let loaded = try await coreDataService.fetchFolders()
            folders = loaded
        } catch {
            errorMessage = "Failed to load folders: \(error.localizedDescription)"
            print("❌ Failed to load folders: \(error)")
        }
        
        isLoading = false
    }
    
    func createFolder(name: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        
        guard !trimmedName.isEmpty else {
            errorMessage = "Folder name cannot be empty"
            return
        }
        
        guard !folders.contains(where: { ($0.name ?? "").lowercased() == trimmedName.lowercased() }) else {
            errorMessage = "A folder with this name already exists"
            return
        }
        
        do {
            _ = try await coreDataService.createFolder(name: trimmedName)
            await loadFolders()
            print("✅ Folder created: \(trimmedName)")
        } catch {
            errorMessage = "Failed to create folder: \(error.localizedDescription)"
            print("❌ Failed to create folder: \(error)")
        }
    }
    
    func deleteFolder(_ folder: FolderEntity) async {
        let folderName = folder.name ?? ""
        
        // Prevent deletion of default folders
        guard folderName != "Temporary Pins" && folderName != "Field Data" else {
            errorMessage = "Cannot delete default folders"
            return
        }
        
        do {
            try await coreDataService.deleteFolder(folder)
            await loadFolders()
            print("✅ Folder deleted: \(folderName)")
        } catch {
            errorMessage = "Failed to delete folder: \(error.localizedDescription)"
            print("❌ Failed to delete folder: \(error)")
        }
    }
    
    func renameFolder(_ folder: FolderEntity, newName: String) async {
        let trimmedName = newName.trimmingCharacters(in: .whitespaces)
        
        guard !trimmedName.isEmpty else {
            errorMessage = "Folder name cannot be empty"
            return
        }
        
        guard !folders.contains(where: {
            $0.id != folder.id && ($0.name ?? "").lowercased() == trimmedName.lowercased()
        }) else {
            errorMessage = "A folder with this name already exists"
            return
        }
        
        do {
            try await coreDataService.updateFolder(folder, name: trimmedName)
            await loadFolders()
            print("✅ Folder renamed to: \(trimmedName)")
        } catch {
            errorMessage = "Failed to rename folder: \(error.localizedDescription)"
            print("❌ Failed to rename folder: \(error)")
        }
    }
    
    // MARK: - Utility Methods
    
    func getFolderItemCount(_ folder: FolderEntity) -> Int {
        return folder.allItemsCount
    }
    
    func isDefaultFolder(_ folder: FolderEntity) -> Bool {
        let folderName = folder.name ?? ""
        return folderName == "Temporary Pins" || folderName == "Field Data"
    }
}
