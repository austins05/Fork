import SwiftUI
import UniformTypeIdentifiers
import CoreLocation

struct ImportKMLView: View {
    let group: APIGroup
    var onImportComplete: () -> Void
    
    @State private var showFilePicker = false
    @State private var isImporting = false
    @State private var importedPins: [KMLPin] = []
    @State private var selectedPins: Set<UUID> = []
    @State private var errorMessage: String?
    @State private var successMessage: String?
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack {
                if importedPins.isEmpty {
                    // Initial state - show import button
                    VStack(spacing: 20) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Import Pins from KML")
                            .font(.title2)
                            .bold()
                        
                        Text("Export pins from Google Maps as KML and import them here")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button {
                            showFilePicker = true
                        } label: {
                            Label("Select KML File", systemImage: "doc.badge.plus")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                    }
                } else {
                    // Show imported pins with selection
                    List {
                        Section {
                            HStack {
                                Text("\(importedPins.count) pins found")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(selectedPins.count == importedPins.count ? "Deselect All" : "Select All") {
                                    if selectedPins.count == importedPins.count {
                                        selectedPins.removeAll()
                                    } else {
                                        selectedPins = Set(importedPins.map { $0.id })
                                    }
                                }
                                .font(.caption)
                            }
                        }
                        
                        Section("Pins to Import") {
                            ForEach(importedPins) { pin in
                                Button {
                                    if selectedPins.contains(pin.id) {
                                        selectedPins.remove(pin.id)
                                    } else {
                                        selectedPins.insert(pin.id)
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: selectedPins.contains(pin.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedPins.contains(pin.id) ? .blue : .gray)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(pin.name)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            
                                            if let description = pin.description, !description.isEmpty {
                                                Text(description)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(2)
                                            }
                                            
                                            Text(String(format: "%.6f, %.6f", pin.coordinate.latitude, pin.coordinate.longitude))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        
                        if let error = errorMessage {
                            Section {
                                Text(error)
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                        
                        if let success = successMessage {
                            Section {
                                Text(success)
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                        }
                    }
                }
                
                if isImporting {
                    ProgressView("Uploading pins...")
                        .padding()
                }
            }
            .navigationTitle("Import KML")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isImporting)
                }
                
                if !importedPins.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            uploadSelectedPins()
                        } label: {
                            if isImporting {
                                ProgressView()
                            } else {
                                Text("Import (\(selectedPins.count))")
                                    .bold()
                            }
                        }
                        .disabled(selectedPins.isEmpty || isImporting)
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.xml, .kml, UTType(filenameExtension: "kml") ?? .xml],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result: result)
            }
        }
    }
    
    private func handleFileImport(result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Unable to access file"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let data = try Data(contentsOf: url)
            let pins = try KMLParser.parse(data: data)
            
            importedPins = pins
            selectedPins = Set(pins.map { $0.id }) // Select all by default
            
            print("✅ Parsed \(pins.count) pins from KML")
        } catch {
            errorMessage = "Failed to parse KML: \(error.localizedDescription)"
            print("❌ KML parse error: \(error)")
        }
    }
    
    private func uploadSelectedPins() {
        let pinsToUpload = importedPins.filter { selectedPins.contains($0.id) }
        guard !pinsToUpload.isEmpty else { return }
        
        isImporting = true
        errorMessage = nil
        successMessage = nil
        
        Task {
            var successCount = 0
            var failCount = 0
            
            for pin in pinsToUpload {
                do {
                    _ = try await PinSyncService.shared.uploadPin(
                        name: pin.name,
                        latitude: pin.coordinate.latitude,
                        longitude: pin.coordinate.longitude,
                        iconName: "mappin",
                        groupId: group.id,
                        folderId: nil
                    )
                    successCount += 1
                } catch {
                    failCount += 1
                    print("❌ Failed to upload pin '\(pin.name)': \(error)")
                }
            }
            
            await MainActor.run {
                isImporting = false
                
                if failCount == 0 {
                    successMessage = "✅ Successfully imported \(successCount) pins to \(group.name)"
                    onImportComplete()
                    
                    // Auto-dismiss after success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        dismiss()
                    }
                } else {
                    errorMessage = "Imported \(successCount) pins, \(failCount) failed"
                }
            }
        }
    }
}

// MARK: - KML UTType Extension
extension UTType {
    static var kml: UTType {
        UTType(filenameExtension: "kml") ?? .xml
    }
}
