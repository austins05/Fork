import SwiftUI
import CoreData

struct FolderDetailView: View {
    let folder: FolderEntity
    let coreDataService: CoreDataService
    
    @State private var pins: [PinEntity] = []
    @State private var fields: [FieldEntity] = []
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var selectedPinId: UUID?
    
    // Batch selection states
    @State private var isSelectionMode = false
    @State private var selectedPins: Set<UUID> = []
    @State private var selectedFields: Set<UUID> = []
    @State private var showBatchActionSheet = false

    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            pinsSection
            fieldsSection
            emptyStateView
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle(folder.name ?? "Unknown")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                leadingToolbarContent
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                trailingToolbarContent
            }
        }
        .onAppear { loadItems() }
        .onReceive(NotificationCenter.default.publisher(for: .coreDataDidChange)) { _ in
            loadItems()
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(activityItems: [url]) {
                    cleanupTempFile()
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedPinId != nil && !isSelectionMode },
            set: { if !$0 { selectedPinId = nil } }
        )) {
            if let pinId = selectedPinId {
                PinActionSheet(pinId: pinId, coreDataService: coreDataService)
            }
        }
        .confirmationDialog("Batch Actions", isPresented: $showBatchActionSheet) {
            batchActionsContent
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var pinsSection: some View {
        if !pins.isEmpty {
            Section("Pins") {
                ForEach(pins) { pin in
                    pinRow(for: pin)
                }
                .onDelete { offsets in
                    if !isSelectionMode {
                        deletePins(at: offsets)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func pinRow(for pin: PinEntity) -> some View {
        HStack {
            if isSelectionMode {
                selectionButton(for: pin.id!, isSelected: selectedPins.contains(pin.id!)) {
                    togglePinSelection(pin.id!)
                }
            }
            
            PinItemRow(pin: pin, onTap: {
                if isSelectionMode {
                    togglePinSelection(pin.id!)
                } else {
                    selectedPinId = pin.id
                }
            }, onShare: {
                sharePin(pin)
            })
        }
    }
    
    @ViewBuilder
    private var fieldsSection: some View {
        if !fields.isEmpty {
            Section("Fields") {
                ForEach(fields) { field in
                    fieldRow(for: field)
                }
                .onDelete { offsets in
                    if !isSelectionMode {
                        deleteFields(at: offsets)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func fieldRow(for field: FieldEntity) -> some View {
        HStack {
            if isSelectionMode {
                selectionButton(for: field.id!, isSelected: selectedFields.contains(field.id!)) {
                    toggleFieldSelection(field.id!)
                }
            }
            
            FieldItemRow(field: field, onTap: {
                if isSelectionMode {
                    toggleFieldSelection(field.id!)
                } else {
                    NotificationCenter.default.post(
                        name: .showFieldOnMap,
                        object: field
                    )
                    dismiss()
                }
            }, onShare: {
                shareField(field)
            })
        }
    }
    
    @ViewBuilder
    private func selectionButton(for id: UUID, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .blue : .gray)
                .font(.title3)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
        if pins.isEmpty && fields.isEmpty {
            Text("No items in this folder")
                .foregroundColor(.secondary)
                .italic()
                .frame(maxWidth: .infinity)
        }
    }
    
    @ViewBuilder
    private var leadingToolbarContent: some View {
        if isSelectionMode {
            Button("Cancel") {
                exitSelectionMode()
            }
        }
    }
    
    @ViewBuilder
    private var trailingToolbarContent: some View {
        HStack(spacing: 15) {
            if isSelectionMode {
                Button {
                    showBatchActionSheet = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(selectedPins.isEmpty && selectedFields.isEmpty)
                
                Button {
                    toggleSelectAll()
                } label: {
                    Text(isAllSelected ? "Deselect All" : "Select All")
                        .font(.subheadline)
                }
            } else {
                Button("Select") {
                    enterSelectionMode()
                }
                
                EditButton()
            }
        }
    }
    
    @ViewBuilder
    private var batchActionsContent: some View {
        if !selectedPins.isEmpty {
            Button("Delete \(selectedPins.count) Pin\(selectedPins.count == 1 ? "" : "s")", role: .destructive) {
                deleteSelectedPins()
            }
            
            Button("Export \(selectedPins.count) Pin\(selectedPins.count == 1 ? "" : "s")") {
                exportSelectedPins()
            }
        }
        
        if !selectedFields.isEmpty {
            Button("Delete \(selectedFields.count) Field\(selectedFields.count == 1 ? "" : "s")", role: .destructive) {
                deleteSelectedFields()
            }
            
            Button("Export \(selectedFields.count) Field\(selectedFields.count == 1 ? "" : "s")") {
                exportSelectedFields()
            }
        }
        
        Button("Cancel", role: .cancel) {}
    }
    
    // MARK: - Selection Mode
    
    private var isAllSelected: Bool {
        selectedPins.count == pins.count && selectedFields.count == fields.count
    }
    
    private func enterSelectionMode() {
        isSelectionMode = true
    }
    
    private func exitSelectionMode() {
        isSelectionMode = false
        selectedPins.removeAll()
        selectedFields.removeAll()
    }
    
    private func togglePinSelection(_ id: UUID) {
        if selectedPins.contains(id) {
            selectedPins.remove(id)
        } else {
            selectedPins.insert(id)
        }
    }
    
    private func toggleFieldSelection(_ id: UUID) {
        if selectedFields.contains(id) {
            selectedFields.remove(id)
        } else {
            selectedFields.insert(id)
        }
    }
    
    private func toggleSelectAll() {
        if isAllSelected {
            selectedPins.removeAll()
            selectedFields.removeAll()
        } else {
            selectedPins = Set(pins.compactMap { $0.id })
            selectedFields = Set(fields.compactMap { $0.id })
        }
    }
    
    // MARK: - Batch Actions
    
    private func deleteSelectedPins() {
        Task {
            for pinId in selectedPins {
                if let pin = pins.first(where: { $0.id == pinId }) {
                    try? await coreDataService.deletePin(pin)
                }
            }
            exitSelectionMode()
            loadItems()
        }
    }
    
    private func deleteSelectedFields() {
        Task {
            for fieldId in selectedFields {
                if let field = fields.first(where: { $0.id == fieldId }) {
                    try? await coreDataService.deleteField(field)
                }
            }
            exitSelectionMode()
            loadItems()
        }
    }
    
    private func exportSelectedPins() {
        let selectedPinEntities = pins.filter { selectedPins.contains($0.id!) }
        
        var exportData: [[String: Any]] = []
        for pin in selectedPinEntities {
            let data: [String: Any] = [
                "id": pin.id?.uuidString ?? "",
                "name": pin.name ?? "Unknown",
                "latitude": pin.latitude,
                "longitude": pin.longitude,
                "iconName": pin.iconName ?? "mappin",
                "dateCreated": pin.dateCreated?.timeIntervalSince1970 ?? 0
            ]
            exportData.append(data)
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted) else {
            return
        }
        
        let fileName = "pins_export.json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try jsonData.write(to: url)
            shareURL = url
            showShareSheet = true
            exitSelectionMode()
        } catch {
            print("Export error: \(error)")
        }
    }
    
    private func exportSelectedFields() {
        let selectedFieldEntities = fields.filter { selectedFields.contains($0.id!) }
        
        var exportData: [[String: Any]] = []
        for field in selectedFieldEntities {
            let data: [String: Any] = [
                "id": field.id?.uuidString ?? "",
                "name": field.name ?? "Unknown",
                "coordinates": field.coordinates,
                "acres": field.acres,
                "color": field.color ?? "",
                "category": field.category ?? "",
                "dateImported": field.dateImported?.timeIntervalSince1970 ?? 0
            ]
            exportData.append(data)
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted) else {
            return
        }
        
        let fileName = "fields_export.json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try jsonData.write(to: url)
            shareURL = url
            showShareSheet = true
            exitSelectionMode()
        } catch {
            print("Export error: \(error)")
        }
    }

    // MARK: - Data Loading
    
    private func loadItems() {
        Task {
            do {
                let loadedPins = try await coreDataService.fetchPins(for: folder)
                let loadedFields = try await coreDataService.fetchFields(for: folder)
                
                await MainActor.run {
                    pins = loadedPins
                    fields = loadedFields
                }
            } catch {
                print("Failed to load items: \(error)")
            }
        }
    }

    private func deletePins(at offsets: IndexSet) {
        for index in offsets {
            let pin = pins[index]
            Task {
                do {
                    try await coreDataService.deletePin(pin)
                    loadItems()
                } catch {
                    print("Failed to delete pin: \(error)")
                }
            }
        }
    }

    private func deleteFields(at offsets: IndexSet) {
        for index in offsets {
            let field = fields[index]
            Task {
                do {
                    try await coreDataService.deleteField(field)
                    loadItems()
                } catch {
                    print("Failed to delete field: \(error)")
                }
            }
        }
    }

    private func sharePin(_ pin: PinEntity) {
        guard let pinId = pin.id,
              let pinName = pin.name,
              let iconName = pin.iconName,
              let dateCreated = pin.dateCreated else {
            print("Pin data incomplete")
            return
        }
        
        let data: [String: Any] = [
            "id": pinId.uuidString,
            "name": pinName,
            "latitude": pin.latitude,
            "longitude": pin.longitude,
            "iconName": iconName,
            "dateCreated": dateCreated.timeIntervalSince1970
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted) else {
            return
        }
        
        let safeName = pinName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        let fileName = "\(safeName).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try jsonData.write(to: url)
            shareURL = url
            showShareSheet = true
        } catch {
            print("Share write error: \(error)")
        }
    }

    private func shareField(_ field: FieldEntity) {
        guard let fieldId = field.id,
              let fieldName = field.name,
              let color = field.color,
              let category = field.category,
              let dateImported = field.dateImported else {
            print("Field data incomplete")
            return
        }
        
        let data: [String: Any] = [
            "id": fieldId.uuidString,
            "name": fieldName,
            "coordinates": field.coordinates,
            "acres": field.acres,
            "color": color,
            "category": category,
            "dateImported": dateImported.timeIntervalSince1970
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted) else {
            return
        }
        
        let safeName = fieldName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        let fileName = "\(safeName).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try jsonData.write(to: url)
            shareURL = url
            showShareSheet = true
        } catch {
            print("Export error: \(error)")
        }
    }

    private func cleanupTempFile() {
        if let url = shareURL {
            try? FileManager.default.removeItem(at: url)
            shareURL = nil
        }
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let showFieldOnMap = Notification.Name("showFieldOnMap")
}
