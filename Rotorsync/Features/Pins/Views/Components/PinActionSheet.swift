import SwiftUI
import CoreData
import CoreLocation

struct PinActionSheet: View {
    let pinId: UUID
    let coreDataService: CoreDataService
    
    @State private var pin: PinEntity?
    @State private var selectedIcon = "mappin"
    @State private var showIconPicker = false
    @State private var showFolderPicker = false
    @State private var showGroupPicker = false
    @State private var folders: [FolderEntity] = []
    @State private var groups: [APIGroup] = []
    @State private var isUploadingToServer = false
    @State private var isLoadingGroups = false
    @State private var uploadError: String?

    @Environment(\.dismiss) private var dismiss

    private let pinIcons = [
        // Weather & Nature
        "leaf", "drop", "flame", "sun.max", "cloud.rain",
        "snowflake", "wind", "bolt", "tornado", "moon.stars",
        "sparkles", "rainbow", "umbrella",
        
        // Location & Navigation
        "mappin", "mappin.circle", "mappin.circle.fill",
        "mappin.and.ellipse", "mappin.slash",
        "location", "location.fill", "location.circle", "location.circle.fill",
        "location.north", "location.north.fill", "location.north.line",
        "scope", "target",
        
        // Symbols & Markers
        "star", "star.fill", "star.circle", "star.circle.fill",
        "flag", "flag.fill", "flag.circle", "flag.circle.fill",
        "exclamationmark.triangle", "exclamationmark.triangle.fill",
        "questionmark.diamond", "questionmark.diamond.fill",
        "xmark.octagon", "xmark.octagon.fill",
        "checkmark.circle", "checkmark.circle.fill",
        "info.circle", "info.circle.fill",
        
        // Shapes
        "circle", "circle.fill", "square", "square.fill",
        "triangle", "triangle.fill", "diamond", "diamond.fill",
        "heart", "heart.fill", "hexagon", "hexagon.fill",
        
        // Objects & Tools
        "wrench", "hammer", "screwdriver", "gearshape",
        "fuel.pump", "building", "house", "tree",
        "car", "truck", "tractor", "bicycle",
        "antenna.radiowaves.left.and.right",
        
        // Agriculture specific
        "leaf.arrow.triangle.circlepath", "drop.triangle",
        "sprinkler", "wind.snow"
    ]
    
    var body: some View {
        NavigationStack {
            if let pin = pin {
                Form {
                    Section("Pin Name") {
                        Text(pin.name ?? "Unknown Pin").font(.headline)
                        Button("Rename") { showRenameAlert() }
                    }

                    Section("Icon") {
                        HStack {
                            Image(systemName: selectedIcon)
                                .foregroundColor(.red)
                                .frame(width: 30)
                            Text("Current Icon")
                            Spacer()
                            Button("Change") { showIconPicker = true }
                        }
                    }
                    
                    Section("Location") {
                        HStack {
                            Text("Latitude")
                            Spacer()
                            Text(String(format: "%.6f", pin.latitude))
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Longitude")
                            Spacer()
                            Text(String(format: "%.6f", pin.longitude))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Section {
                        Button {
                            driveToLocation()
                        } label: {
                            Label("Drive To", systemImage: "car.fill")
                                .foregroundColor(.blue)
                        }
                        
                        Button("Open in Google Maps") { openInMaps() }
                        Button("Delete Pin", role: .destructive) { deletePin() }
                    }

                    Section("Organization") {
                        Button("Move to Folder") {
                            Task { await loadFoldersAndShowPicker() }
                        }
                        .foregroundColor(.blue)
                        .disabled(isUploadingToServer || isLoadingGroups)
                        
                        Button {
                            Task { await loadGroupsAndShowPicker() }
                        } label: {
                            HStack {
                                Text("Save to Group")
                                if isLoadingGroups {
                                    Spacer()
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                        }
                        .foregroundColor(.green)
                        .disabled(isUploadingToServer || isLoadingGroups)
                    }
                    
                    if isUploadingToServer {
                        Section {
                            HStack {
                                ProgressView()
                                Text("Syncing to server...")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if let error = uploadError {
                        Section {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }

                    Section {
                        Button("Open in Google Maps") { openInMaps() }
                        Button("Delete Pin", role: .destructive) { deletePin() }
                    }
                }
                .navigationTitle("Edit Pin")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
                .sheet(isPresented: $showIconPicker) {
                    IconPickerSheet(selectedIcon: $selectedIcon, icons: pinIcons) { newIcon in
                        Task { await updateIcon(newIcon) }
                    }
                }
                .sheet(isPresented: $showFolderPicker) {
                    FolderPickerSheet(
                        folders: folders,
                        currentFolder: pin.folder,
                        onSelect: { folder in
                            Task { await moveToFolder(folder) }
                        }
                    )
                }
                .sheet(isPresented: $showGroupPicker) {
                    GroupPickerSheet(
                        groups: groups,
                        isLoading: isLoadingGroups,
                        onSelect: { group in
                            Task { await saveToGroup(group: group) }
                        }
                    )
                }
            } else {
                ProgressView("Loading...")
                    .onAppear { loadPin() }
            }
        }
    }

    private func loadPin() {
        do {
            let request = PinEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", pinId as CVarArg)
            let pins = try PersistenceController.shared.container.viewContext.fetch(request)
            pin = pins.first
            selectedIcon = pin?.iconName ?? "mappin"
        } catch {
            print("Failed to load pin: \(error)")
        }
    }

    private func showRenameAlert() {
        guard let currentPin = pin else { return }
        dismiss()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
                  let root = scene.windows.first?.rootViewController else { return }

            let alert = UIAlertController(title: "Rename Pin", message: nil, preferredStyle: .alert)
            alert.addTextField { textField in
                textField.text = currentPin.name ?? "Pin"
                textField.placeholder = "Pin name"
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
                if let newName = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                   !newName.isEmpty {
                    Task {
                        do {
                            try await coreDataService.updatePin(currentPin, name: newName)
                        } catch {
                            print("Failed to rename pin: \(error)")
                        }
                    }
                }
            })
            root.present(alert, animated: true)
        }
    }

    private func updateIcon(_ newIcon: String) async {
        guard let currentPin = pin else { return }
        do {
            try await coreDataService.updatePin(currentPin, iconName: newIcon)
            await MainActor.run {
                selectedIcon = newIcon
                pin?.iconName = newIcon
            }
        } catch {
            print("Failed to update icon: \(error)")
        }
    }

    private func loadFoldersAndShowPicker() async {
        do {
            let loadedFolders = try await coreDataService.fetchFolders()
            await MainActor.run {
                folders = loadedFolders
                showFolderPicker = true
            }
        } catch {
            print("Failed to load folders: \(error)")
        }
    }
    
    private func loadGroupsAndShowPicker() async {
        await MainActor.run {
            isLoadingGroups = true
            uploadError = nil
            showGroupPicker = true
        }
        
        do {
            let loadedGroups = try await PinSyncService.shared.getUserGroups()
            
            print("✅ Loaded \(loadedGroups.count) groups: \(loadedGroups.map { $0.name })")
            
            await MainActor.run {
                groups = loadedGroups
                isLoadingGroups = false
            }
        } catch {
            await MainActor.run {
                uploadError = "Failed to load groups: \(error.localizedDescription)"
                isLoadingGroups = false
            }
            print("❌ Failed to load groups: \(error)")
        }
    }
    
    private func saveToGroup(group: APIGroup) async {
        guard let currentPin = pin else { return }
        
        await MainActor.run {
            isUploadingToServer = true
            uploadError = nil
        }
        
        do {
            let apiPin = try await PinSyncManager.shared.uploadPinToServer(
                name: currentPin.name ?? "Pin",
                latitude: currentPin.latitude,
                longitude: currentPin.longitude,
                iconName: currentPin.iconName ?? "mappin",
                groupId: group.id,
                folderId: nil
            )
            
            // Save the server pin ID to mark it as shared
            try await coreDataService.updatePin(
                currentPin,
                serverPinId: apiPin.id
            )
            
            print("✅ Pin uploaded to server: \(apiPin.id) in group: \(group.name)")
            
            await MainActor.run {
                isUploadingToServer = false
                showGroupPicker = false
                dismiss()
            }
            
            await MainActor.run {
                showSuccessAlert(message: "Pin saved to \(group.name) and synced to all group members!")
            }
        } catch {
            await MainActor.run {
                isUploadingToServer = false
                uploadError = "Upload failed: \(error.localizedDescription)"
            }
            print("❌ Failed to upload pin: \(error)")
        }
    }

    private func moveToFolder(_ folder: FolderEntity) async {
        guard let currentPin = pin else { return }
        do {
            try await coreDataService.movePin(currentPin, to: folder)
            await MainActor.run { dismiss() }
        } catch {
            print("Failed to move pin: \(error)")
        }
    }

    private func deletePin() {
        guard let currentPin = pin else { return }
        Task {
            do {
                try await coreDataService.deletePin(currentPin)
                await MainActor.run { dismiss() }
            } catch {
                print("Failed to delete pin: \(error)")
            }
        }
    }

    private func openInMaps() {
        guard let currentPin = pin else { return }
        MapUtilities.openInGoogleMaps(coordinate: currentPin.coordinate, label: currentPin.name)
        dismiss()
    }
    
    private func showSuccessAlert(message: String) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        
        let alert = UIAlertController(title: "Success", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        root.present(alert, animated: true)
    }
    
    private func driveToLocation() {
        guard let currentPin = pin else { return }
        let coord = currentPin.coordinate
        
        // Google Maps navigation URL
        let googleNavURL = URL(string: "comgooglemaps://?daddr=\(coord.latitude),\(coord.longitude)&directionsmode=driving")!
        
        if UIApplication.shared.canOpenURL(googleNavURL) {
            UIApplication.shared.open(googleNavURL)
            print("✅ Started navigation in Google Maps")
        } else {
            // Fallback to Apple Maps
            let appleNavURL = URL(string: "maps://?daddr=\(coord.latitude),\(coord.longitude)&dirflg=d")!
            UIApplication.shared.open(appleNavURL)
            print("ℹ️ Google Maps not installed, using Apple Maps")
        }
        dismiss()
    }
}
