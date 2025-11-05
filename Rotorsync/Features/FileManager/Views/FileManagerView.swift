import SwiftUI
import CoreData

struct FileManagerView: View {
    let coreDataService: CoreDataService
    @State private var folders: [FolderEntity] = []
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(folders) { folder in
                    NavigationLink {
                        FolderDetailView(folder: folder, coreDataService: coreDataService)
                    } label: {
                        FolderRow(folder: folder)
                    }
                }
                .onDelete(perform: deleteFolders)
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("File Manager")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        EditButton()
                        Button {
                            newFolderName = ""
                            showNewFolderAlert = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                        }
                    }
                }
            }
            .alert("New Folder", isPresented: $showNewFolderAlert) {
                TextField("Folder Name", text: $newFolderName)
                    .autocapitalization(.words)
                Button("Cancel", role: .cancel) {}
                Button("Create") { createFolder() }
                    .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .onAppear { loadFolders() }
            .onReceive(NotificationCenter.default.publisher(for: .coreDataDidChange)) { _ in
                loadFolders()
            }
        }
    }

    private func loadFolders() {
        Task {
            do {
                let loaded = try await coreDataService.fetchFolders()
                await MainActor.run {
                    folders = loaded
                }
            } catch {
                print("Failed to load folders: \(error)")
            }
        }
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty,
              !folders.contains(where: { ($0.name ?? "").lowercased() == name.lowercased() }) else { return }
        
        Task {
            do {
                _ = try await coreDataService.createFolder(name: name)
                loadFolders()
            } catch {
                print("Failed to create folder: \(error)")
            }
        }
    }

    private func deleteFolders(at offsets: IndexSet) {
        for index in offsets {
            let folder = folders[index]
            let folderName = folder.name ?? ""
            // Prevent deletion of default folders
            guard folderName != "Temporary Pins" && folderName != "Field Data" else {
                continue
            }
            
            Task {
                do {
                    try await coreDataService.deleteFolder(folder)
                    loadFolders()
                } catch {
                    print("Failed to delete folder: \(error)")
                }
            }
        }
    }
}
