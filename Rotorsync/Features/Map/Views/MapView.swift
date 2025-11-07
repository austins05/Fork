import SwiftUI
import MapKit
import CoreLocation
import Combine
import Foundation
import ZIPFoundation
import SQLite3
import UniformTypeIdentifiers
import CoreData

struct MapView: View {
    private let coreDataService = CoreDataService()
    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var viewModel = MapViewModel()
    
    @State private var mapStyle: AppMapStyle = .hybrid
    @State private var showMapStyleDialog = false
    @State private var showSettingsSheet = false
    @State private var overlayScale: CGFloat = 1.0
    @State private var shareLocation: Bool = true
    @State private var showTemperatureGraph: Bool = false
    @State private var temperatureGraphSize: CGSize = CGSize(width: 250, height: 150)
    @State private var temperatureGraphPosition: TemperatureGraphPosition = .topLeft
    @State private var temperatureGraphScale: CGFloat = 1.0

    @State private var droppedPins: [DroppedPinViewModel] = []
    @State private var groupPins: [APIPin] = []
    @State private var selectedPinId: UUID?
    @State private var selectedGroupPin: APIPin?
    @State private var selectedDevice: Device?

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isInitialLoad = true

    @State private var isTracking = false
    @State private var trackedLocations: [CLLocation] = []
    @State private var path: [CLLocationCoordinate2D] = []
    @State private var totalDistance: Double = 0.0
    @State private var startTime: Date?

    @State private var showUserDialog = false
    @State private var pressCount = 0
    @State private var pressTimer: Timer?

    @State private var importedFields: [FieldData] = []
    @State private var showImportedFields = true
    @State private var showImport = false
    @State private var isLoadingMPZ = false
    @State private var importError: String?
    @State private var selectedField: FieldData?
    @State private var showFieldDetails = false

    @State private var showFileManager = false
    @State private var refreshTrigger = false
    
    @State private var showGroupManagement = false
    
    @State private var isUserCentered = true  // Add this flag
    @State private var lastUserLocation: CLLocation?
    
    @State private var mapCenter: CLLocationCoordinate2D?
    
    @State private var hasSetInitialRegion = false  // Add this flag
    @State private var userTrackingMode: MKUserTrackingMode = .none
    @State private var shouldForceUpdate = false  // Add this with other @State variables


    private let refreshTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private var userDeviceDescription: String {
        struct Serial: Codable { let id: String; let name: String }
        struct User: Codable { let id: String; let name: String?; let email: String?; let serialNumber: Serial? }
        guard let data = UserDefaults.standard.data(forKey: "userData"),
              let user = try? JSONDecoder().decode(User.self, from: data) else { return "—" }
        return user.serialNumber?.name ?? "No device assigned"
    }

    private var durationString: String {
        guard let start = startTime, isTracking else { return "00:00" }
        let i = Date().timeIntervalSince(start)
        let m = Int(i / 60); let s = Int(i) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var showImportError: Binding<Bool> {
        Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
    }

    private func setInitialRegion(animated: Bool) {
        guard let userLoc = locationManager.userLocation?.coordinate else { return }
        
        // Create a clean overview - not too zoomed in
        let region = MKCoordinateRegion(
            center: userLoc,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        
        cameraPosition = .region(region)
    }
    
    private func reloadPins() async {
        do {
            let pins = try await coreDataService.fetchAllPins()
            let viewModels = pins.map { DroppedPinViewModel(from: $0) }
            await MainActor.run {
                droppedPins = viewModels
            }
        } catch {
            print("Failed to reload pins: \(error)")
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            MapRepresentable(
                cameraPosition: $cameraPosition,
                droppedPins: $droppedPins,
                groupPins: $groupPins,
                importedFields: $importedFields,
                showImportedFields: $showImportedFields,
                path: $path,
                mapStyle: $mapStyle,
                userTrackingMode: $userTrackingMode,
                mapCenter: $mapCenter,
                shouldForceUpdate: $shouldForceUpdate,
                devices: viewModel.devices,
                onPinTapped: { pin in selectedPinId = pin.id },
                onGroupPinTapped: { pin in selectedGroupPin = pin },
                onDeviceTapped: { selectedDevice = $0 },
                onFieldTapped: { selectedField = $0; showFieldDetails = true },
                onLongPressPinDropped: { coord, name in
                    Task { await handlePinDrop(coordinate: coord, name: name) }
                }
            )
            .ignoresSafeArea()
            .onAppear {
                locationManager.requestLocationPermission()
                Task {
                    await viewModel.fetchDevices()
                    
                    // Only set initial region once
                    if !hasSetInitialRegion {
                        setInitialRegion(animated: false)
                        hasSetInitialRegion = true
                    }
                    
                    await reloadPins()
                    await loadGroupPins()
                    await ensureDefaultFolders()
                }
            }
            .onReceive(locationManager.$userLocation) { newLoc in
               if let new = newLoc, isTracking {
                   if let last = trackedLocations.last {
                       totalDistance += new.distance(from: last) / 1609.34
                   }
                   trackedLocations.append(new)
                   path.append(new.coordinate)
               }
               // Don't auto-center here - let user control it
           }
            .onReceive(refreshTimer) { _ in }
            .onReceive(NotificationCenter.default.publisher(for: .coreDataDidChange)) { _ in
                Task { await reloadPins() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showGroupPinOnMap)) { notification in
                if let pin = notification.object as? APIPin {
                    let coordinate = CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
                    let region = MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                    setCameraPosition(.region(region), animated: true)
                }
            }
            .onReceive(SharedFieldStorage.shared.$shouldImportToMap) { shouldImport in
                if shouldImport {
                    print("📍 Importing fields from SharedFieldStorage")
                    print("📍 Pending fields count: (SharedFieldStorage.shared.pendingFieldsToImport.count)")
                    print("📍 Current importedFields count BEFORE: (importedFields.count)")
                    importedFields.append(contentsOf: SharedFieldStorage.shared.pendingFieldsToImport)
                    SharedFieldStorage.shared.clearPendingFields()
                    print("📍 Current importedFields count AFTER: (importedFields.count)")
                    print("📍 Imported field IDs: (importedFields.map { $0.id })")
                    updateMapRegion(animated: true)

                    let count = importedFields.count
                    showAlert(title: "Fields Imported", message: "Added \(count) fields from Tabula to map")
                }
            }
            .onReceive(SharedFieldStorage.shared.$shouldClearAllFields) { shouldClear in
                if shouldClear {
                    let count = importedFields.count
                    importedFields.removeAll()
                    SharedFieldStorage.shared.shouldClearAllFields = false
                    showAlert(title: "Fields Cleared", message: "Removed \(count) field\(count == 1 ? "" : "s") from map")
                }
            }
            .id(refreshTrigger)
            
            CrosshairOverlay(
               userLocation: locationManager.userLocation,
               mapCenter: mapCenter  // This should update as you pan
           )
           .frame(maxWidth: .infinity, maxHeight: .infinity)
           .allowsHitTesting(false)

            overlayView()

            // Temperature graph overlay (positioned below speed/altitude overlay)
            TemperatureGraphOverlay(
                size: $temperatureGraphSize,
                isVisible: $showTemperatureGraph,
                presetPosition: $temperatureGraphPosition,
                graphScale: $temperatureGraphScale
            )

            bottomButtonsView()
        }

        .confirmationDialog("User Location Options", isPresented: $showUserDialog) {
            if isTracking {
                Button("Stop Tracking") {
                    isTracking = false; path = []; trackedLocations = []; totalDistance = 0.0; startTime = nil
                }
            } else {
                Button("Start Tracking") {
                    if let loc = locationManager.userLocation {
                        trackedLocations = [loc]; path = [loc.coordinate]; totalDistance = 0.0; startTime = Date(); isTracking = true
                    }
                }
            }
            Button("Drop Focus Pin") {
                if let c = locationManager.userLocation?.coordinate {
                    Task {
                        await handlePinDrop(coordinate: c, name: "Focus Point \(droppedPins.count + 1)")
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }

        .sheet(isPresented: Binding(
            get: { selectedPinId != nil },
            set: { if !$0 { selectedPinId = nil } }
        )) {
            if let pinId = selectedPinId {
                PinActionSheet(pinId: pinId, coreDataService: coreDataService)
            }
        }
        
        .sheet(item: $selectedGroupPin) { pin in
            GroupPinDetailSheet(pin: pin)
                .presentationDetents([.medium])
        }

        .sheet(item: $selectedDevice) { dev in
            DeviceActionSheet(device: dev) {
                openInGoogleMaps(CLLocationCoordinate2D(latitude: dev.latitude ?? 0,
                                                        longitude: dev.longitude ?? 0))
            }
            .presentationDetents([.fraction(0.28)])
        }

        .sheet(isPresented: $showFieldDetails) {
            if let f = selectedField {
                FieldDetailsSheet(field: f) { selectedField = nil; showFieldDetails = false }
            }
        }

        .fileImporter(isPresented: $showImport,
                      allowedContentTypes: [.zip, UTType(filenameExtension: "mpz") ?? .zip, .data],
                      allowsMultipleSelection: false) { handleImportResult(result: $0) }

        .alert("Import Error", isPresented: showImportError) { Button("OK") {} }
        message: { Text(importError ?? "Unknown error") }

        .overlay { if isLoadingMPZ { ProgressView("Importing MPZ...").progressViewStyle(.circular).padding().background(Color.black.opacity(0.6)).cornerRadius(10) } }

        .sheet(isPresented: $showFileManager) {
            FileManagerView(coreDataService: coreDataService)
        }
        
        .sheet(isPresented: $showGroupManagement) {
            GroupManagementView()
        }
    }

    @ViewBuilder
    private func overlayView() -> some View {
        HStack(spacing: 20) {
            
            // Left - Time and Distance (only when tracking)
            if isTracking {
                VStack(alignment: .leading, spacing: 4) {
                    // Time with milliseconds
                    HStack(spacing: 2) {
                        Text(durationString)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                        
                        Text(".\(String(format: "%02d", Int(Date().timeIntervalSince(startTime ?? Date()).truncatingRemainder(dividingBy: 1) * 100)))")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.orange.opacity(0.7))
                    }
                    
                    Text(String(format: "%.1f mi", totalDistance))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 1, height: 50)
            }
            
            // Speed
            VStack(spacing: 4) {
                Text(extractSpeed(from: locationManager.speedString))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("MPH")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 1, height: 50)
            
            // Altitude (same size as speed now)
            VStack(spacing: 4) {
                Text(extractAltitude(from: locationManager.altitudeString))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("ft")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.75))
        )
        .fixedSize() // This prevents it from taking full width/height
        .padding(.top, 8)
        .padding(.leading, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Helper functions to extract numbers from formatted strings
    private func extractSpeed(from speedString: String) -> String {
        // speedString format: "0.0 mph" or "—"
        if speedString == "—" { return "0" }
        let components = speedString.components(separatedBy: " ")
        guard let number = components.first else { return "0" }
        return String(format: "%.0f", Double(number) ?? 0)
    }

    private func extractAltitude(from altitudeString: String) -> String {
        // altitudeString format: "0 ft" or "—"
        if altitudeString == "—" { return "0" }
        let components = altitudeString.components(separatedBy: " ")
        guard let number = components.first else { return "0" }
        return number
    }
    
    @ViewBuilder private func bottomButtonsView() -> some View {
        VStack(spacing: 15) {
            Button { showMapStyleDialog.toggle() } label: {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
                    .shadow(radius: 5)
            }
            .confirmationDialog("Select Map Type", isPresented: $showMapStyleDialog, titleVisibility: .visible) {
                ForEach(AppMapStyle.allCases, id: \.self) { style in
                    Button(style.displayName) { mapStyle = style }
                }
                Button("Cancel", role: .cancel) {}
            }

            Button { showSettingsSheet.toggle() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
                    .shadow(radius: 5)
            }
            .sheet(isPresented: $showSettingsSheet) {
                OverlaySettingsView(
                    overlayScale: $overlayScale,
                    shareLocation: $shareLocation,
                    showTemperatureGraph: $showTemperatureGraph,
                    temperatureGraphPosition: $temperatureGraphPosition,
                    temperatureGraphScale: $temperatureGraphScale
                )
                .presentationDetents([.fraction(0.55)])
            }

            Button { showImport = true } label: {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
                    .shadow(radius: 5)
            }

            if !importedFields.isEmpty {
                Button { showImportedFields.toggle(); updateMapRegion(animated: true) } label: {
                    Image(systemName: showImportedFields ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                        .shadow(radius: 5)
                }
            }

            Button {
                userTrackingMode = userTrackingMode == .followWithHeading ? .none : .followWithHeading
            } label: {
                Image(systemName: userTrackingMode == .followWithHeading ? "location.north.line.fill" : "location.north.line")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .padding()
                    .background(userTrackingMode == .followWithHeading ? Color.blue.opacity(0.8) : Color.black.opacity(0.6))
                    .clipShape(Circle())
                    .shadow(radius: 5)
            }
              
            // Auto-center button (centers on user with nice overview)
            Button {
                centerToOverview()
            } label: {
                Image(systemName: "location.viewfinder")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
                    .shadow(radius: 5)
            }
            
            Button { showFileManager = true } label: {
                Image(systemName: "folder.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
                    .shadow(radius: 5)
            }
            
            Button { showGroupManagement = true } label: {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.purple.opacity(0.8))
                    .clipShape(Circle())
                    .shadow(radius: 5)
            }
        }
        .padding(.bottom, 40)
        .padding(.trailing, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private func updateMapRegion(animated: Bool = true) {
        let devLocs = viewModel.devices.compactMap {
            $0.latitude != nil && $0.longitude != nil ?
            CLLocationCoordinate2D(latitude: $0.latitude!, longitude: $0.longitude!) : nil
        }
        var coords = devLocs
        if shareLocation, let u = locationManager.userLocation { coords.append(u.coordinate) }
        if showImportedFields && !importedFields.isEmpty {
            for f in importedFields { coords.append(contentsOf: f.coordinates) }
        }
        guard !coords.isEmpty else {
            setCameraPosition(.region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                                                         span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))),
                              animated: animated)
            return
        }
        let lats = coords.map { $0.latitude }
        let lons = coords.map { $0.longitude }
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let latD = max((maxLat - minLat) * 1.2, 0.005)
        let lonD = max((maxLon - minLon) * 1.2, 0.005)
        let span = MKCoordinateSpan(latitudeDelta: latD, longitudeDelta: lonD)
        setCameraPosition(.region(MKCoordinateRegion(center: center, span: span)), animated: animated)
    }

    private func centerOnUser(animated: Bool = true) {
        guard let loc = locationManager.userLocation else { return }
        let r = MKCoordinateRegion(
            center: loc.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001)  // Changed from 0.005 to 0.001 (5x more zoomed in)
        )
        setCameraPosition(.region(r), animated: animated)
    }

    private func setCameraPosition(_ position: MapCameraPosition, animated: Bool) {
       if animated {
           withAnimation(.easeInOut(duration: 0.6)) {
               cameraPosition = position
           }
       } else {
           cameraPosition = position
       }
   }

    private func openInGoogleMaps(_ coord: CLLocationCoordinate2D) {
        let g = URL(string: "comgooglemaps://?q=\(coord.latitude),\(coord.longitude)")!
        let a = URL(string: "maps://?q=\(coord.latitude),\(coord.longitude)")!
        if UIApplication.shared.canOpenURL(g) { UIApplication.shared.open(g) }
        else { UIApplication.shared.open(a) }
    }

    private func loadGroupPins() async {
        do {
            // Get all user's groups
            let groups = try await PinSyncService.shared.getUserGroups()
            
            // Fetch pins from all groups (including your own)
            var allGroupPins: [APIPin] = []
            for group in groups {
                let pins = try await PinSyncService.shared.getGroupPins(groupId: group.id)
                allGroupPins.append(contentsOf: pins)
            }
            
            await MainActor.run {
                groupPins = allGroupPins
            }
            
            print("✅ Loaded \(allGroupPins.count) total group pins")
        } catch {
            print("❌ Failed to load group pins: \(error)")
        }
    }
    
    private func handleImportResult(result: Result<[URL], Error>) {
        isLoadingMPZ = true
        Task {
            do {
                let urls = try result.get()
                guard let url = urls.first else { throw NSError(domain: "No file", code: 0) }
                guard url.startAccessingSecurityScopedResource() else { throw NSError(domain: "Access", code: -1) }
                defer { url.stopAccessingSecurityScopedResource() }
                let fields = try await importMPZ(from: url)
                await MainActor.run {
                    importedFields.append(contentsOf: fields)
                    Task { await saveFieldsToCoreData(fields) }
                    let acres = fields.reduce(0.0) { $0 + $1.acres }
                    showAlert(title: "Import Complete",
                              message: "Loaded \(fields.count) fields, \(String(format: "%.1f", acres)) total acres")
                    isLoadingMPZ = false
                }
            } catch {
                await MainActor.run { importError = error.localizedDescription; isLoadingMPZ = false }
            }
        }
    }
    
    private func centerToOverview() {
        guard let loc = locationManager.userLocation else {
            print("⚠️ No user location available")
            return
        }
        
        print("🔵 Center button pressed - Current location: \(loc.coordinate.latitude), \(loc.coordinate.longitude)")
        
        let region = MKCoordinateRegion(
            center: loc.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        
        // Disable tracking
        userTrackingMode = .none
        
        // Set flag to force this one update
        shouldForceUpdate = true
        
        // Set the camera position
        cameraPosition = .region(region)
        
        print("✅ Camera position set to: \(region.center.latitude), \(region.center.longitude)")
    }

    private func showAlert(title: String, message: String) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        root.present(a, animated: true)
    }

    private func saveFieldsToCoreData(_ fields: [FieldData]) async {
        do {
            let folders = try await coreDataService.fetchFolders()
            guard let fieldDataFolder = folders.first(where: { $0.name == "Field Data" }) else { return }
            
            for field in fields {
                let coords = field.coordinates.map { ["lat": $0.latitude, "lng": $0.longitude] }
                _ = try await coreDataService.createField(
                    name: field.name,
                    coordinates: coords,
                    acres: field.acres,
                    color: field.color,
                    category: field.category ?? "General",
                    application: field.application,
                    fieldDescription: field.description,
                    folder: fieldDataFolder
                )
            }
            await MainActor.run {
                showAlert(title: "Saved", message: "\(fields.count) fields saved to Core Data")
            }
        } catch {
            await MainActor.run {
                showAlert(title: "Save Failed", message: error.localizedDescription)
            }
        }
    }

    private func handlePinDrop(coordinate: CLLocationCoordinate2D, name: String) async {
        do {
            let folders = try await coreDataService.fetchFolders()
            guard let tempFolder = folders.first(where: { $0.name == "Temporary Pins" }) else { return }
            
            _ = try await coreDataService.createPin(
                name: name,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                iconName: "mappin",
                folder: tempFolder
            )
            await reloadPins()
        } catch {
            print("Failed to save pin: \(error)")
        }
    }

    private func ensureDefaultFolders() async {
        do {
            let existingFolders = try await coreDataService.fetchFolders()
            
            if !existingFolders.contains(where: { $0.name == "Field Data" }) {
                _ = try await coreDataService.createFolder(name: "Field Data")
            }
            
            if !existingFolders.contains(where: { $0.name == "Temporary Pins" }) {
                _ = try await coreDataService.createFolder(name: "Temporary Pins")
            }
        } catch {
            print("Failed to ensure default folders: \(error)")
        }
    }

    private func importMPZ(from url: URL) async throws -> [FieldData] {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: url, to: temp)
        let contents = try FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)
        guard let sdb = contents.first(where: { $0.pathExtension.lowercased() == "sdb" }) else {
            throw NSError(domain: "No SDB", code: 1)
        }
        let fields = try processSDB(at: sdb)
        try? FileManager.default.removeItem(at: temp)
        return fields
    }

    private func processSDB(at url: URL) throws -> [FieldData] {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw NSError(domain: "Open DB", code: 2) }
        defer { sqlite3_close(db) }

        let query = """
        SELECT s.item_id, s.coordinates, s.line_color, s.fill_color,
               i.name, i.description, i.short_name, i.type,
               CASE WHEN i.name IS NOT NULL AND TRIM(i.name) != '' THEN TRIM(i.name)
                    WHEN i.short_name IS NOT NULL AND TRIM(i.short_name) != '' THEN TRIM(i.short_name)
                    ELSE 'Field ' || s.item_id END as display_name,
               plkp.value as application_data, cat.name as category_name
        FROM t_shape s
        LEFT JOIN t_item i ON s.item_id = i.id
        LEFT JOIN t_item cat ON i.feature_class_id = cat.id
        LEFT JOIN t_property_lkp plkp ON i.feature_class_id = plkp.item_id
        WHERE s.coordinates IS NOT NULL
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { throw NSError(domain: "Prepare", code: 3) }
        defer { sqlite3_finalize(stmt) }

        var fields: [FieldData] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = Int(sqlite3_column_int(stmt, 0))
            let blob = sqlite3_column_blob(stmt, 1)
            let bytes = sqlite3_column_bytes(stmt, 1)
            if blob != nil && bytes > 0 {
                let data = Data(bytes: blob!, count: Int(bytes))
                let coords = parseWKBCoordinates(wkbData: data)
                if !coords.isEmpty {
                    let name = sqlite3_column_text(stmt, 8).flatMap { String(cString: $0) } ?? "Unknown"
                    let desc = sqlite3_column_text(stmt, 5).flatMap { String(cString: $0) }
                    let cat = sqlite3_column_text(stmt, 10).flatMap { String(cString: $0) }
                    let app = sqlite3_column_text(stmt, 9).flatMap { String(cString: $0) }
                    let col = getColorFromCategory(categoryName: cat ?? "")
                    let acres = calculateAreaAcres(coordinates: coords)
                    fields.append(FieldData(id: id, name: name, coordinates: coords,
                                            acres: acres, color: col, category: cat,
                                            application: app, description: desc))
                }
            }
        }
        return fields
    }

    private func parseWKBCoordinates(wkbData: Data) -> [CLLocationCoordinate2D] {
        guard wkbData.count >= 28 else { return [] }
        let header = 12
        let coordData = wkbData.subdata(in: header..<wkbData.count)
        let per = 16
        let count = coordData.count / per
        var out: [CLLocationCoordinate2D] = []
        for i in 0..<count {
            let off = i * per
            guard off + 16 <= coordData.count else { break }
            let lat = coordData.subdata(in: off..<off+8).withUnsafeBytes { $0.load(as: Double.self) }
            let lng = coordData.subdata(in: off+8..<off+16).withUnsafeBytes { $0.load(as: Double.self) }
            if isValidCoordinate(lat: lat, lng: lng) {
                out.append(CLLocationCoordinate2D(latitude: lat, longitude: lng))
            }
        }
        return filterCoordinateOutliers(coordinates: out)
    }

    private func isValidCoordinate(lat: Double, lng: Double) -> Bool {
        lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180 &&
        !(lat == 0 && lng == 0) && abs(lat) > 0.01 && abs(lng) > 0.01 && abs(lat) < 85
    }

    private func filterCoordinateOutliers(coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard coordinates.count >= 10 else { return coordinates }
        let lats = coordinates.map { $0.latitude }.sorted()
        let lngs = coordinates.map { $0.longitude }.sorted()
        let medLat = lats[lats.count/2]
        let medLng = lngs[lngs.count/2]
        let maxDeg = 50 / 111.0
        return coordinates.filter {
            abs($0.latitude - medLat) <= maxDeg && abs($0.longitude - medLng) <= maxDeg
        }
    }

    private func calculateAreaAcres(coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count >= 3 else { return 0 }
        let cenLat = coordinates.reduce(0.0) { $0 + $1.latitude } / Double(coordinates.count)
        let latM = 111319.5
        let lngM = latM * cos(cenLat * .pi / 180)
        var area = 0.0
        let n = coordinates.count
        for i in 0..<n {
            let cur = coordinates[i]
            let nxt = coordinates[(i+1) % n]
            let x1 = cur.longitude * lngM; let y1 = cur.latitude * latM
            let x2 = nxt.longitude * lngM; let y2 = nxt.latitude * latM
            area += x1 * y2 - x2 * y1
        }
        area = abs(area) / 2
        return area / 4046.86
    }

    private func getColorFromCategory(categoryName: String) -> String {
        let c = categoryName.lowercased().trimmingCharacters(in: .whitespaces)
        let colors: [String: String] = [
            "green": "#00FF7F",
            "teal": "#00FFFF",
            "pink": "#FF69B4",
            "yellow": "#FFFF00",
            "blue": "#0080FF",
            "red": "#FF4500",
            "orange": "#FF8C00",
            "purple": "#9966FF"
        ]
        return colors[c] ?? "#FF6B6B"
    }
}

#Preview { MapView() }
