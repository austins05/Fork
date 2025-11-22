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
    @State private var showSettingsSheet = false
    @State private var overlayScale: CGFloat = 1.0
    @State private var shareLocation: Bool = true
    @State private var showTemperatureGraph: Bool = false
    @State private var temperatureGraphSize: CGSize = CGSize(width: 250, height: 150)
    @State private var temperatureGraphPosition: TemperatureGraphPosition = .topLeft
    @State private var temperatureGraphScale: CGFloat = 1.0

    // Button visibility settings
    @AppStorage("showMeasureButton") private var showMeasureButton: Bool = true
    @AppStorage("showGroupsButton") private var showGroupsButton: Bool = true
    @AppStorage("showFilesButton") private var showFilesButton: Bool = true
    @AppStorage("showMPZImportButton") private var showMPZImportButton: Bool = true
    @AppStorage("showPanicButton") private var showPanicButton: Bool = true
    @AppStorage("flightMode") private var flightMode: Bool = false
    @AppStorage("useHeadingUp") private var useHeadingUp: Bool = true

    @State private var droppedPins: [DroppedPinViewModel] = []
    @State private var groupPins: [APIPin] = []
    @State private var selectedPinId: UUID?
    @State private var selectedGroupPin: APIPin?
    @State private var selectedDevice: Device?
    @State private var hoveredField: FieldData?

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

    @State private var showFileManager = false
    @State private var refreshTrigger = false
    
    @State private var showGroupManagement = false
    
    @State private var isUserCentered = true  // Add this flag
    @State private var lastUserLocation: CLLocation?
    
    @State private var mapCenter: CLLocationCoordinate2D?
    
    @State private var hasSetInitialRegion = false  // Add this flag
    @State private var userTrackingMode: MKUserTrackingMode = .none
    @State private var shouldForceUpdate = false  // Add this with other @State variables

    // Measurement tool
    @State private var isMeasuring = false
    @State private var measurementPins: [(coordinate: CLLocationCoordinate2D, name: String)] = []
    @State private var totalMeasurementDistance: Double = 0.0
    @State private var segmentDistances: [Double] = [] // Distance from each pin to the next

    // Navigation
    @StateObject private var navigationManager: NavigationManager
    @State private var isNavigating = false

    // Field selection
    @State private var isFieldSelectionMode = false
    @State private var selectedFieldIds: Set<Int> = []
    @State private var showSelectionInfo = false
    @State private var circleDrawingPath: [CGPoint] = []
    @State private var targetRegion: MKCoordinateRegion?
    @State private var hiddenFieldsStack: [FieldData] = []
    @State private var showRouteSelection = false
    @State private var selectedRouteIndex: Int?
    @State private var allRoutes: [NavigationRoute] = []
    @State private var navigationRoute: NavigationRoute?
    @State private var alternateRoutes: [NavigationRoute] = []
    @State private var isAddingWaypoint: Bool = false
    @State private var navigationCameraAltitude: CLLocationDistance = 800
    @State private var lastSpeedZoomUpdate: Date = Date()
    @State private var forceOverlayRefresh: Bool = false

    // Fly To mode
    @State private var isFlyingTo = false
    @State private var flyToDestination: CLLocationCoordinate2D?
    @State private var flyToLine: [CLLocationCoordinate2D] = []
    @State private var currentHeading: Double = 0 // Heading from movement
    @State private var headingLocationHistory: [CLLocation] = [] // Last few locations for heading calculation
    @State private var speedHistory: [(speed: Double, timestamp: Date)] = [] // For average speed calculation

    // Flight Mode projection ray
    @State private var projectionRayLine: [CLLocationCoordinate2D] = []
    @State private var projection5MinMark: CLLocationCoordinate2D?
    @State private var projection10MinMark: CLLocationCoordinate2D?
    @State private var projection15MinMark: CLLocationCoordinate2D?
    @State private var lastProjectionUpdate = Date()

    init() {
        let locationMgr = LocationManager.shared
        let navMgr = NavigationManager(locationManager: locationMgr)
        _navigationManager = StateObject(wrappedValue: navMgr)
    }

    // MARK: - Measurement Functions
    private func calculateDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLocation.distance(from: toLocation) // meters
    }

    private func formatDistance(_ meters: Double) -> String {
        let feet = meters * 3.28084
        if feet < 5280 {
            return String(format: "%.0f ft", feet)
        } else {
            let miles = feet / 5280
            return String(format: "%.2f mi", miles)
        }
    }

    private func addMeasurementPin(coordinate: CLLocationCoordinate2D) {
        let pinNumber = measurementPins.count + 1
        let name = "M\(pinNumber)"
        measurementPins.append((coordinate: coordinate, name: name))

        // Calculate distance from previous pin
        if measurementPins.count > 1 {
            let prevPin = measurementPins[measurementPins.count - 2]
            let distance = calculateDistance(from: prevPin.coordinate, to: coordinate)
            segmentDistances.append(distance)
            totalMeasurementDistance += distance
        }
    }

    private func clearMeasurements() {
        measurementPins.removeAll()
        segmentDistances.removeAll()
        totalMeasurementDistance = 0.0
    }

    private func undoLastPin() {
        guard !measurementPins.isEmpty else { return }

        // Remove the last pin
        measurementPins.removeLast()

        // If there was a segment distance for this pin, remove it and recalculate total
        if !segmentDistances.isEmpty {
            segmentDistances.removeLast()
            totalMeasurementDistance = segmentDistances.reduce(0, +)
        }
    }

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

    // MARK: - View Components

    @ViewBuilder
    private var mapLayer: some View {
        MapRepresentable(
            cameraPosition: $cameraPosition,
            droppedPins: $droppedPins,
            groupPins: $groupPins,
            importedFields: $importedFields,
            showImportedFields: $showImportedFields,
            hoveredField: $hoveredField,
            path: $path,
            mapStyle: $mapStyle,
            userTrackingMode: $userTrackingMode,
            mapCenter: $mapCenter,
            shouldForceUpdate: $shouldForceUpdate,
            isMeasuring: $isMeasuring,
            measurementPins: $measurementPins,
            navigationRoute: $navigationRoute,
            allRoutes: $allRoutes,
            selectedRouteIndex: $selectedRouteIndex,
            isNavigating: $isNavigating,
            waypoints: $navigationManager.waypoints,
            isAddingWaypoint: $isAddingWaypoint,
            navigationCameraAltitude: $navigationCameraAltitude,
            flyToLine: $flyToLine,
            remainingRoutePolyline: $navigationManager.remainingRoutePolyline,
            forceOverlayRefresh: $forceOverlayRefresh,
            projectionRayLine: $projectionRayLine,
            projection5MinMark: $projection5MinMark,
            projection10MinMark: $projection10MinMark,
            projection15MinMark: $projection15MinMark,
            flightMode: $flightMode,
            usingTCPGPS: .constant(LocationManager.shared.gpsSettings.tcpEnabled),
            tcpUserLocation: .constant(LocationManager.shared.gpsSettings.tcpEnabled ? LocationManager.shared.tcpGPSClient.currentLocation : nil),
            isFieldSelectionMode: $isFieldSelectionMode,
            selectedFieldIds: $selectedFieldIds,
            circleDrawingPath: $circleDrawingPath,
            targetRegion: $targetRegion,
            devices: viewModel.devices,
            onPinTapped: handlePinTapped,
            onGroupPinTapped: handleGroupPinTapped,
            onDeviceTapped: handleDeviceTapped,
            onFieldTapped: handleFieldTapped,
            onLongPressPinDropped: handleLongPressPinDropped,
            onMeasurementTap: handleMeasurementTap,
            onRouteTapped: handleRouteTapped,
            onWaypointTapped: handleWaypointTapped,
            onAddWaypoint: handleAddWaypoint,
            onPinDoubleTapped: handlePinDoubleTapped,
            onGroupPinDoubleTapped: handleGroupPinDoubleTapped
        )
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var crosshairLayer: some View {
        CrosshairOverlay(
            userLocation: locationManager.userLocation,
            mapCenter: mapCenter
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var overlaysLayer: some View {
        Group {

            overlayView()

            // Temperature graph overlay
            TemperatureGraphOverlay(
                size: $temperatureGraphSize,
                isVisible: $showTemperatureGraph,
                presetPosition: $temperatureGraphPosition,
                graphScale: $temperatureGraphScale
            )

            // Field info card
            if let field = hoveredField {
                VStack {
                    Spacer()
                    FieldInfoCard(field: field)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 100)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .animation(.easeInOut(duration: 0.3), value: hoveredField?.id)
            }

            // Measurement tool display
            if isMeasuring {
                HStack(alignment: .top) {
                    Spacer()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MEASURE MODE")
                            .font(.caption.bold())
                            .foregroundColor(.blue)

                        Text("Tap map to drop pins")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))

                        if !measurementPins.isEmpty {
                            Divider()
                                .opacity(0.2)

                            ScrollView {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(0..<segmentDistances.count, id: \.self) { index in
                                        HStack(spacing: 4) {
                                            Text("M\(index + 1) → M\(index + 2):")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.8))
                                            Text(formatDistance(segmentDistances[index]))
                                                .font(.caption.weight(.semibold))
                                                .foregroundColor(.yellow)
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 200)

                            if totalMeasurementDistance > 0 {
                                Divider()
                                    .opacity(0.2)
                                HStack(spacing: 4) {
                                    Text("Total:")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.white)
                                    Text(formatDistance(totalMeasurementDistance))
                                        .font(.subheadline.weight(.bold))
                                        .foregroundColor(.green)
                                }
                            }

                            HStack(spacing: 8) {
                                Button {
                                    undoLastPin()
                                } label: {
                                    Text("Undo")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.orange)
                                        .cornerRadius(8)
                                }

                                Button {
                                    clearMeasurements()
                                } label: {
                                    Text("Clear")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.red)
                                        .cornerRadius(8)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: 140)
                    .padding(8)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(12)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.trailing, 110)
                .padding(.top, 28)
                .ignoresSafeArea(.all, edges: .top)
            }

            bottomButtonsView()
        }
    }

    // MARK: - Event Handlers

    private func handlePinTapped(_ pin: DroppedPinViewModel) {
        selectedPinId = pin.id
    }

    private func handleGroupPinTapped(_ pin: APIPin) {
        selectedGroupPin = pin
    }

    private func handleDeviceTapped(_ device: Device) {
        selectedDevice = device
    }

    private func handleFieldTapped(_ field: FieldData) {
        selectedField = field
    }

    private func handleLongPressPinDropped(coord: CLLocationCoordinate2D, name: String) {
        Task { await handlePinDrop(coordinate: coord, name: name) }
    }

    private func handleMeasurementTap(coord: CLLocationCoordinate2D) {
        addMeasurementPin(coordinate: coord)
    }

    private func handleRouteTapped(routeIndex: Int) {
        selectedRouteIndex = routeIndex
    }

    private func handleWaypointTapped(index: Int) {
        showWaypointRemoveAlert(index: index)
    }

    private func handleAddWaypoint(coordinate: CLLocationCoordinate2D) {
        navigationManager.addWaypoint(coordinate)
        isAddingWaypoint = false
    }

    private func handlePinDoubleTapped(_ pin: DroppedPinViewModel) {
        if flightMode {
            print("✈️ [DOUBLE-TAP] Flight mode enabled - starting Fly To")
            startFlyTo(to: pin.coordinate)
        } else {
            print("🚗 [DOUBLE-TAP] Normal mode - starting Drive To navigation")
            startNavigation(to: pin.coordinate)
        }
    }

    private func handleGroupPinDoubleTapped(_ pin: APIPin) {
        let coordinate = CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
        if flightMode {
            print("✈️ [DOUBLE-TAP] Flight mode enabled - starting Fly To (group pin)")
            startFlyTo(to: coordinate)
        } else {
            print("🚗 [DOUBLE-TAP] Normal mode - starting Drive To navigation (group pin)")
            startNavigation(to: coordinate)
        }
    }

    // MARK: - Lifecycle Handlers

    private func handleOnAppear() {
        locationManager.requestLocationPermission()
        Task {
            await viewModel.fetchDevices()

            if !hasSetInitialRegion {
                setInitialRegion(animated: false)
                hasSetInitialRegion = true
            }

            await reloadPins()
            await loadGroupPins()
            await ensureDefaultFolders()
        }
    }

    private func handleLocationUpdate(_ newLoc: CLLocation?) {
        // Track location if tracking is enabled
        if let new = newLoc, isTracking {
            if let last = trackedLocations.last {
                totalDistance += new.distance(from: last) / 1609.34
            }
            trackedLocations.append(new)
            path.append(new.coordinate)
        }

        // Speed-based zoom during navigation (works with both follow modes)
        if isNavigating, let location = newLoc, userTrackingMode != .none {
            adjustZoomForSpeed(speed: location.speed, coordinate: location.coordinate)
        }

        // Track heading and speed for flight mode
        if (isFlyingTo || flightMode), let location = newLoc {
            updateFlightModeData(location: location)
        }

        // Update fly-to line
        if isFlyingTo, let destination = flyToDestination, let location = newLoc {
            flyToLine = [location.coordinate, destination]
        }

        // Update flight mode projection
        if flightMode {
            updateFlightModeProjection()
        }
    }

    private func updateFlightModeData(location: CLLocation) {
        // Track location history for heading calculation
        headingLocationHistory.append(location)
        if headingLocationHistory.count > 3 {
            headingLocationHistory.removeFirst()
        }

        // Track speed history
        let now = Date()
        speedHistory.append((speed: location.speed, timestamp: now))
        speedHistory.removeAll { now.timeIntervalSince($0.timestamp) > 60 }

        // Calculate heading
        if headingLocationHistory.count >= 2 {
            let oldest = headingLocationHistory.first!
            let newest = location
            currentHeading = calculateBearing(from: oldest.coordinate, to: newest.coordinate)
            print("🧭 [HEADING] From movement: \(currentHeading)°")
        } else if location.course >= 0 {
            currentHeading = location.course
            print("🧭 [HEADING] From GPS course: \(currentHeading)°")
        }
    }

    private func handleShowGroupPin(_ notification: Notification) {
        if let pin = notification.object as? APIPin {
            let coordinate = CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
            let region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            setCameraPosition(.region(region), animated: true)
        }
    }

    private func handleFieldImport(_ shouldImport: Bool) {
        if shouldImport {
            print("📍 Importing fields from SharedFieldStorage")
            print("📍 Pending fields count: \(SharedFieldStorage.shared.pendingFieldsToImport.count)")
            print("📍 Current importedFields count BEFORE: \(importedFields.count)")
            importedFields.append(contentsOf: SharedFieldStorage.shared.pendingFieldsToImport)
            SharedFieldStorage.shared.clearPendingFields()
            print("📍 Current importedFields count AFTER: \(importedFields.count)")
            print("📍 Imported field IDs: \(importedFields.map { $0.id })")
            updateMapRegion(animated: true)

            let count = importedFields.count
            showAlert(title: "Fields Imported", message: "Added \(count) fields from Tabula to map")
        }
    }

    private func handleFieldClear(_ shouldClear: Bool) {
        if shouldClear {
            let count = importedFields.count
            importedFields.removeAll()
            SharedFieldStorage.shared.shouldClearAllFields = false
            showAlert(title: "Fields Cleared", message: "Removed \(count) field\(count == 1 ? "" : "s") from map")
        }
    }

    private func removeSelectedFields() {
        let count = selectedFieldIds.count
        importedFields.removeAll { selectedFieldIds.contains($0.id) }
        selectedFieldIds.removeAll()
        isFieldSelectionMode = false
        showAlert(title: "Fields Removed", message: "Removed \(count) field\(count == 1 ? "" : "s") from map")
    }

    private func zoomToField(_ field: FieldData) {
        guard !field.coordinates.isEmpty else { return }

        print("🎯 [ZOOM] Zooming to field: \(field.name)")

        // Disable tracking mode if active
        if userTrackingMode != .none {
            userTrackingMode = .none
            print("🎯 [ZOOM] Disabled tracking mode")
        }

        // Calculate bounding box of field coordinates
        let lats = field.coordinates.map { $0.latitude }
        let lons = field.coordinates.map { $0.longitude }

        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            print("🎯 [ZOOM] Failed to get min/max coordinates")
            return
        }

        // Calculate center
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        // Calculate span with some padding (1.3x for nice framing)
        let latDelta = max((maxLat - minLat) * 1.3, 0.001)
        let lonDelta = max((maxLon - minLon) * 1.3, 0.001)

        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )

        print("🎯 [ZOOM] Center: \(center.latitude), \(center.longitude)")
        print("🎯 [ZOOM] Span: \(latDelta), \(lonDelta)")

        // Use native MapKit region setting
        targetRegion = region
        print("🎯 [ZOOM] Target region set")
    }

    private func hideField(_ field: FieldData) {
        print("🗑️ Removing field from map: \(field.name)")

        // Remove from map
        importedFields.removeAll { $0.id == field.id }

        // Remove from selection
        selectedFieldIds.remove(field.id)

        // Add to undo stack
        hiddenFieldsStack.append(field)
        print("📚 Undo stack size: \(hiddenFieldsStack.count)")
    }

    private func undoHideField() {
        print("↩️ Undoing remove")

        guard let field = hiddenFieldsStack.popLast() else { return }

        print("📚 Restoring: \(field.name), stack size: \(hiddenFieldsStack.count)")

        // Add back to map
        importedFields.append(field)

        // Add back to selection
        selectedFieldIds.insert(field.id)
    }

    // MARK: - Computed Properties

    private var selectedFields: [FieldData] {
        importedFields.filter { selectedFieldIds.contains($0.id) }
    }

    // MARK: - Main Body (Simplified)

    var body: some View {
        ZStack(alignment: .topLeading) {
            mapLayer
                .onAppear(perform: handleOnAppear)
                .onReceive(locationManager.$userLocation, perform: handleLocationUpdate)
                .onReceive(refreshTimer) { _ in }
                .onReceive(NotificationCenter.default.publisher(for: .coreDataDidChange)) { _ in
                    Task { await reloadPins() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .showGroupPinOnMap), perform: handleShowGroupPin)
                .onReceive(SharedFieldStorage.shared.$shouldImportToMap, perform: handleFieldImport)
                .onReceive(SharedFieldStorage.shared.$shouldClearAllFields, perform: handleFieldClear)
                .id(refreshTrigger)

            crosshairLayer
            overlaysLayer
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
                PinActionSheet(
                    pinId: pinId,
                    coreDataService: coreDataService,
                    onStartNavigation: { coordinate in
                        startNavigation(to: coordinate)
                    },
                    onStartFlyTo: { coordinate in
                        startFlyTo(to: coordinate)
                    }
                )
            }
        }
        
        .sheet(item: $selectedGroupPin) { pin in
            GroupPinDetailSheet(
                pin: pin,
                onStartNavigation: { coordinate in
                    startNavigation(to: coordinate)
                }
            )
            .presentationDetents([.medium])
        }

        .sheet(item: $selectedDevice) { dev in
            DeviceActionSheet(device: dev) {
                openInGoogleMaps(CLLocationCoordinate2D(latitude: dev.latitude ?? 0,
                                                        longitude: dev.longitude ?? 0))
            }
            .presentationDetents([.fraction(0.28)])
        }

        .sheet(item: $selectedField) { field in
            FieldDetailsSheet(field: field) { selectedField = nil }
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

        .overlay(alignment: .topTrailing) {
            // Field selection toggle button at top-right
            Button {
                isFieldSelectionMode.toggle()
                if !isFieldSelectionMode {
                    selectedFieldIds.removeAll()
                    showSelectionInfo = false
                } else if !selectedFieldIds.isEmpty {
                    showSelectionInfo = true
                }
            } label: {
                Image(systemName: isFieldSelectionMode ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(isFieldSelectionMode ? Color.green.opacity(0.8) : Color.black.opacity(0.6))
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            .padding(.top, 60)
            .padding(.trailing, 16)
        }
        .ignoresSafeArea(edges: .top)

        .overlay(alignment: .trailing) {
            if !selectedFieldIds.isEmpty && isFieldSelectionMode {
                FieldSelectionSidebar(
                    selectedFields: selectedFields,
                    onDeselectAll: {
                        selectedFieldIds.removeAll()
                    },
                    onRemoveSelected: {
                        removeSelectedFields()
                    },
                    onDismiss: {
                        showSelectionInfo = false
                    },
                    onFieldTap: { field in
                        zoomToField(field)
                    },
                    onHideField: { field in
                        hideField(field)
                    },
                    show: showSelectionInfo,
                    undoCount: hiddenFieldsStack.count,
                    onUndo: undoHideField
                )
                .ignoresSafeArea(edges: .all)
            }
        }

        .onChange(of: selectedFieldIds) { oldValue, newValue in
            // Show selection sheet when fields are selected in selection mode
            if isFieldSelectionMode && !newValue.isEmpty {
                showSelectionInfo = true
            } else if newValue.isEmpty {
                showSelectionInfo = false
            }
            // Trigger overlay refresh to update highlighting
            forceOverlayRefresh.toggle()
        }

        .onChange(of: flightMode) { oldValue, newValue in
            // Clear projection when flight mode is turned off
            if !newValue {
                projectionRayLine = []
                projection5MinMark = nil
                projection10MinMark = nil
                projection15MinMark = nil
                print("🚁 [FLIGHT MODE] Projection cleared")
            }
        }

        .overlay(alignment: .leading) {
            // Route selection sidebar
            if showRouteSelection {
                RouteSelectionSheet(
                    navigationManager: navigationManager,
                    selectedRouteIndex: $selectedRouteIndex,
                    isAddingWaypoint: $isAddingWaypoint,
                    onStartNavigation: {
                        if let index = selectedRouteIndex, index < allRoutes.count {
                            let route = allRoutes[index]
                            navigationRoute = route
                            navigationManager.startNavigation(with: route)
                            isNavigating = true
                            showRouteSelection = false
                            allRoutes = []
                            selectedRouteIndex = nil
                            isAddingWaypoint = false
                            navigationManager.clearWaypoints()
                        }
                    },
                    onCancel: {
                        showRouteSelection = false
                        allRoutes = []
                        selectedRouteIndex = nil
                        isAddingWaypoint = false
                        navigationManager.clearWaypoints()
                    },
                    onRecalculateRoutes: {
                        // Recalculate routes with updated highway preference
                        if let dest = navigationManager.destination {
                            print("🔄 [MAP VIEW] Recalculating routes with updated settings")
                            navigationManager.calculateRoutes(to: dest)
                        }
                    }
                )
            }
        }

        .overlay(alignment: .leading) {
            if isNavigating {
                InAppNavigationView(
                    navigationManager: navigationManager,
                    isNavigating: $isNavigating,
                    onEndNavigation: {
                        print("🔄 [MAP VIEW] onEndNavigation callback triggered")
                        stopNavigation()
                    }
                )
            }
        }

        .overlay(alignment: .top) {
            if isFlyingTo, let destination = flyToDestination {
                CompassTapeOverlay(
                    currentHeading: currentHeading,
                    destinationBearing: calculateDestinationBearing(),
                    destination: destination,
                    currentLocation: locationManager.userLocation,
                    isFlyingTo: $isFlyingTo,
                    averageSpeed: calculateAverageSpeed(),
                    onEndFlyTo: {
                        print("🔄 [MAP VIEW] onEndFlyTo callback triggered")
                        stopFlyTo()
                    }
                )
                .ignoresSafeArea(.all, edges: .top)
            }
        }

        .onReceive(navigationManager.$status) { status in
            switch status {
            case .selectingRoute(let routes):
                // Show all routes on map for selection
                print("🗺️ [MAP VIEW] selectingRoute status received with \(routes.count) routes")
                print("🗺️ [MAP VIEW] Waypoints: \(navigationManager.waypoints.count)")

                allRoutes = routes
                selectedRouteIndex = 0 // Default to first route
                showRouteSelection = true
                isAddingWaypoint = true // Automatically enable waypoint mode

                // Force overlay update when routes change
                forceOverlayRefresh.toggle()

                print("🗺️ [MAP VIEW] Showing \(routes.count) route options - waypoint mode enabled, overlay refresh triggered")
            case .navigating:
                if let route = navigationManager.selectedRoute {
                    navigationRoute = route
                }
                // Auto-enable tracking when navigation starts using user preference
                userTrackingMode = useHeadingUp ? .followWithHeading : .follow
                print("🧭 [MAP VIEW] Navigation started - auto-enabled tracking (heading up: \(useHeadingUp))")
            case .idle, .arrived:
                print("🧭 [MAP VIEW] Navigation ending - clearing all routes")
                navigationRoute = nil
                allRoutes = []
                selectedRouteIndex = nil
                alternateRoutes = []
                isNavigating = false
                navigationManager.clearWaypoints()
                userTrackingMode = .none
                forceOverlayRefresh.toggle() // Force overlay to refresh
                print("🧭 [MAP VIEW] Navigation ended and cleaned up")
            default:
                break
            }
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
                    
                    Text(String(format: "%.2f mi", totalDistance))
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
                    temperatureGraphScale: $temperatureGraphScale,
                    mapStyle: $mapStyle,
                    showMeasureButton: $showMeasureButton,
                    showGroupsButton: $showGroupsButton,
                    showFilesButton: $showFilesButton,
                    showMPZImportButton: $showMPZImportButton,
                    showPanicButton: $showPanicButton,
                    headingUpMode: $useHeadingUp,
                    onMeasureTool: {
                        isMeasuring.toggle()
                        if !isMeasuring {
                            clearMeasurements()
                        }
                    },
                    onGroups: {
                        showGroupManagement = true
                    },
                    onFiles: {
                        showFileManager = true
                    },
                    onMPZImport: {
                        showImport = true
                    },
                    onPanic: {
                        loadAllRTSOrders()
                    }
                )
                .presentationDetents([.fraction(0.70)])
            }

            if showMPZImportButton {
                Button { showImport = true } label: {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                        .shadow(radius: 5)
                }
            }

            // Panic button - loads all RTS orders
            if showPanicButton {
                Button {
                    loadAllRTSOrders()
                } label: {
                    Image("panic-attack")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .padding(8)
                        .background(Color.red.opacity(0.9))
                        .clipShape(Circle())
                        .shadow(radius: 5)
                }
            }

            // Auto-center button - toggles tracking on/off using setting preference
            Button {
                if userTrackingMode == .none {
                    // Enable tracking with the user's preferred mode
                    userTrackingMode = useHeadingUp ? .followWithHeading : .follow
                    RemoteLogger.shared.log("🗺️ [MAP] Auto-center: Enabled (heading up: \(useHeadingUp))")
                    print("🗺️ [MAP] Auto-center enabled with mode: \(userTrackingMode.rawValue)")
                } else {
                    // Disable tracking
                    userTrackingMode = .none
                    RemoteLogger.shared.log("🗺️ [MAP] Auto-center: Disabled")
                    print("🗺️ [MAP] Auto-center disabled")
                }
            } label: {
                Image(systemName: userTrackingMode == .none ? "location" :
                                 (useHeadingUp ? "location.north.line.fill" : "location.fill"))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .padding()
                    .background(userTrackingMode == .none ?
                               Color.black.opacity(0.6) : Color.blue.opacity(0.7))
                    .clipShape(Circle())
                    .shadow(radius: 5)
            }

            if showFilesButton {
                Button { showFileManager = true } label: {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                        .shadow(radius: 5)
                }
            }

            // Measurement tool button
            if showMeasureButton {
                Button {
                    isMeasuring.toggle()
                    if !isMeasuring {
                        clearMeasurements()
                    }
                } label: {
                    Image(systemName: isMeasuring ? "ruler.fill" : "ruler")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .padding()
                        .background(isMeasuring ? Color.blue.opacity(0.8) : Color.black.opacity(0.6))
                        .clipShape(Circle())
                        .shadow(radius: 5)
                }
            }

            if showGroupsButton {
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

    private func loadAllRTSOrders() {
        Task {
            do {
                print("🚨 [PANIC] Loading all RTS orders...")

                // Fetch all field maps for customer 5429
                guard let url = URL(string: "https://jobs.rotorsync.com/api/field-maps/customer/5429") else {
                    throw URLError(.badURL)
                }

                let (data, _) = try await URLSession.shared.data(from: url)
                let apiResponse = try JSONDecoder().decode(JobsAPIResponse.self, from: data)

                // Filter for RTS orders using the rts boolean field
                let rtsOrders = apiResponse.data.filter { $0.rts }
                print("🚨 [PANIC] Found \(rtsOrders.count) RTS orders")

                // Color conversion map
                let colorMap: [String: String] = [
                    "red": "#FF0000", "orange": "#FF8C00", "yellow": "#FFFF00",
                    "green": "#00FF00", "teal": "#00FFFF", "blue": "#0000FF",
                    "purple": "#9966FF", "pink": "#FF69B4", "magenta": "#FF00FF",
                    "gray": "#404040", "grey": "#404040", "black": "#000000", "white": "#FFFFFF"
                ]

                var newFields: [FieldData] = []

                for job in rtsOrders {
                    // Check cache first
                    if let cached = FieldGeometryCache.shared.getCachedGeometry(fieldId: job.id) {
                        let boundaries = cached.boundaries
                        let sprayLines = cached.sprayLines
                        print("✅ Cache hit for \(job.id) - \(boundaries.count) boundaries")

                        // Convert colors
                        var fillColor = ""
                        if let colorName = job.color {
                            let name = colorName.lowercased().trimmingCharacters(in: .whitespaces)
                            fillColor = name.hasPrefix("#") ? colorName : (colorMap[name] ?? "")
                        }

                        var strokeColor: String? = nil
                        if let boundaryColorName = job.boundaryColor, !boundaryColorName.isEmpty {
                            let name = boundaryColorName.lowercased().trimmingCharacters(in: .whitespaces)
                            strokeColor = name.hasPrefix("#") ? boundaryColorName : colorMap[name]
                        }

                        let contractorDash = job.contractor.flatMap { ContractorDashSettingsManager.shared.getDashColor(for: $0) }

                        // Create field entries for each boundary
                        let sortedBoundaries = boundaries.sorted { calculatePolygonArea($0) > calculatePolygonArea($1) }
                        for (index, boundary) in sortedBoundaries.enumerated() {
                            let fieldName = sortedBoundaries.count > 1 ? "#\(job.id) \(index + 1)/\(sortedBoundaries.count)" : "#\(job.id)"
                            let fieldData = FieldData(
                                id: job.id + index * 10000, jobId: job.id,
                                name: fieldName,
                                coordinates: boundary,
                                acres: job.area * 2.47105 / Double(sortedBoundaries.count),
                                color: fillColor,
                                boundaryColor: strokeColor,
                                contractorDashColor: contractorDash,
                                category: job.status,
                                application: nil,
                                description: nil,
                                prodDupli: job.prodDupli,
                                productList: job.productList,
                                notes: job.notes,
                                address: job.address,
                                source: .tabula,
                                crop: job.crop,
                                nominalAcres: (job.areaNominal ?? 0) * 2.47105,
                                workedCoordinates: sprayLines
                            )
                            newFields.append(fieldData)
                        }
                    } else {
                        print("⚠️ No cache for \(job.id) - skipping")
                    }
                }

                await MainActor.run {
                    importedFields.append(contentsOf: newFields)
                    Task { await saveFieldsToCoreData(newFields) }
                    showAlert(title: "🚨 Panic Mode Activated!",
                             message: "Loaded \(newFields.count) RTS orders onto the map")
                }

                print("✅ [PANIC] Successfully loaded \(newFields.count) RTS fields")
            } catch {
                print("❌ [PANIC] Error: \(error)")
                await MainActor.run {
                    showAlert(title: "Error", message: "Failed to load RTS orders: \(error.localizedDescription)")
                }
            }
        }
    }

    private func calculatePolygonArea(_ coords: [CLLocationCoordinate2D]) -> Double {
        guard coords.count >= 3 else { return 0 }
        var area: Double = 0
        for i in 0..<coords.count {
            let j = (i + 1) % coords.count
            area += coords[i].latitude * coords[j].longitude
            area -= coords[j].latitude * coords[i].longitude
        }
        return abs(area / 2.0)
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
                              message: "Loaded \(fields.count) fields, \(String(format: "%.2f", acres)) total acres")
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

    // MARK: - Navigation Functions
    private func startNavigation(to coordinate: CLLocationCoordinate2D) {
        print("🗺️ [MAP VIEW] startNavigation called with coordinate: \(coordinate.latitude), \(coordinate.longitude)")
        navigationManager.calculateRoutes(to: coordinate)
        print("🗺️ [MAP VIEW] calculateRoutes called on NavigationManager")
    }

    private func stopNavigation() {
        print("🗺️ [MAP VIEW] ========== STOPPING NAVIGATION ==========")

        // Immediately set state to trigger cleanup
        isNavigating = false

        // Clear navigation manager state FIRST
        navigationManager.stopNavigation()
        navigationManager.clearWaypoints()

        // Clear ALL route display state
        navigationRoute = nil
        alternateRoutes = []
        allRoutes = []
        selectedRouteIndex = nil
        userTrackingMode = .none
        navigationCameraAltitude = 800

        // Force overlay refresh IMMEDIATELY
        forceOverlayRefresh.toggle()

        print("🗺️ [MAP VIEW] First cleanup pass complete")

        // Secondary cleanup after delay to ensure overlays removed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.navigationRoute = nil
            self.allRoutes = []
            self.forceOverlayRefresh.toggle()
            print("🗺️ [MAP VIEW] Secondary cleanup pass complete - route MUST be gone")
        }
    }

    // MARK: - Fly To Functions
    private func startFlyTo(to coordinate: CLLocationCoordinate2D) {
        print("✈️ [MAP VIEW] Starting Fly To mode")
        flyToDestination = coordinate
        isFlyingTo = true

        // Initial line from current location to destination
        if let currentLoc = locationManager.userLocation {
            flyToLine = [currentLoc.coordinate, coordinate]

            // Set initial heading from GPS course if available
            if currentLoc.course >= 0 {
                currentHeading = currentLoc.course
                print("✈️ [MAP VIEW] Initial heading from GPS: \(currentHeading)°")
            } else {
                // Use bearing to destination as initial heading if no course
                currentHeading = calculateBearing(from: currentLoc.coordinate, to: coordinate)
                print("✈️ [MAP VIEW] Initial heading from bearing to dest: \(currentHeading)°")
            }
        }

        print("✈️ [MAP VIEW] Fly To mode active")
    }

    private func stopFlyTo() {
        print("✈️ [MAP VIEW] Stopping Fly To mode")
        isFlyingTo = false
        flyToDestination = nil
        flyToLine = []
        headingLocationHistory = []
        speedHistory = []
        currentHeading = 0
        print("✈️ [MAP VIEW] Fly To mode stopped")
    }

    private func calculateAverageSpeed() -> Double {
        guard !speedHistory.isEmpty else { return 0 }

        // Calculate average speed from last minute of data
        let totalSpeed = speedHistory.reduce(0.0) { $0 + $1.speed }
        return totalSpeed / Double(speedHistory.count)
    }

    private func calculateBearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180

        let dLon = lon2 - lon1

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi

        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    private func calculateDestinationBearing() -> Double? {
        guard let destination = flyToDestination, let location = locationManager.userLocation else {
            print("🧭 [BEARING] No destination or location")
            return nil
        }

        let bearing = calculateBearing(from: location.coordinate, to: destination)
        print("🧭 [BEARING] Destination at \(bearing)°, current heading: \(currentHeading)°, relative: \(bearing - currentHeading)°")
        return bearing
    }

    // MARK: - Flight Mode Projection Functions

    /// Calculate a destination coordinate from a starting point, bearing (degrees), and distance (meters)
    private func calculateDestinationCoordinate(from start: CLLocationCoordinate2D, bearing: Double, distance: Double) -> CLLocationCoordinate2D {
        let earthRadius = 6371000.0 // meters

        let bearingRadians = bearing * .pi / 180
        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180

        let angularDistance = distance / earthRadius

        let lat2 = asin(sin(lat1) * cos(angularDistance) +
                        cos(lat1) * sin(angularDistance) * cos(bearingRadians))

        let lon2 = lon1 + atan2(sin(bearingRadians) * sin(angularDistance) * cos(lat1),
                                cos(angularDistance) - sin(lat1) * sin(lat2))

        return CLLocationCoordinate2D(
            latitude: lat2 * 180 / .pi,
            longitude: lon2 * 180 / .pi
        )
    }

    /// Update flight mode projection ray and time markers based on current heading and speed
    private func updateFlightModeProjection() {
        // Throttle updates to 3x per second (0.33 seconds)
        guard Date().timeIntervalSince(lastProjectionUpdate) > 0.33 else { return }
        lastProjectionUpdate = Date()
        guard let location = locationManager.userLocation, flightMode else {
            // Clear projection if flight mode is off or no location
            projectionRayLine = []
            projection5MinMark = nil
            projection10MinMark = nil
            projection15MinMark = nil
            return
        }

        // Calculate heading from movement (last 30 feet) or GPS course
        var projectionHeading: Double = 0
        if headingLocationHistory.count >= 2 {
            let oldest = headingLocationHistory.first!
            let newest = location
            projectionHeading = calculateBearing(from: oldest.coordinate, to: newest.coordinate)
            print("🚁 [FLIGHT MODE] Heading from movement: \(projectionHeading)°")
        } else if location.course >= 0 {
            // Fallback to GPS course when not enough movement data
            projectionHeading = location.course
            print("🚁 [FLIGHT MODE] Heading from GPS course: \(projectionHeading)°")
        } else {
            // No heading data available
            print("🚁 [FLIGHT MODE] No heading data available")
            projectionRayLine = []
            projection5MinMark = nil
            projection10MinMark = nil
            projection15MinMark = nil
            return
        }

        // Calculate average speed (m/s)
        let avgSpeed = calculateAverageSpeed()
        guard avgSpeed > 0 else {
            print("🚁 [FLIGHT MODE] No speed data (stationary)")
            projectionRayLine = []
            projection5MinMark = nil
            projection10MinMark = nil
            projection15MinMark = nil
            return
        }

        print("🚁 [FLIGHT MODE] Avg speed: \(avgSpeed) m/s (\(avgSpeed * 2.23694) mph)")

        // Calculate projection points
        let currentCoord = location.coordinate

        // 5 minute projection
        let distance5min = avgSpeed * 5 * 60 // meters
        let mark5 = calculateDestinationCoordinate(from: currentCoord, bearing: projectionHeading, distance: distance5min)
        projection5MinMark = mark5

        // 10 minute projection
        let distance10min = avgSpeed * 10 * 60 // meters
        let mark10 = calculateDestinationCoordinate(from: currentCoord, bearing: projectionHeading, distance: distance10min)
        projection10MinMark = mark10

        // 15 minute projection
        let distance15min = avgSpeed * 15 * 60 // meters
        let mark15 = calculateDestinationCoordinate(from: currentCoord, bearing: projectionHeading, distance: distance15min)
        projection15MinMark = mark15

        // Create projection ray line from current location to 15-minute mark
        projectionRayLine = [currentCoord, mark15]

        print("🚁 [FLIGHT MODE] Projection updated - 5min: \(formatDistance(distance5min)), 10min: \(formatDistance(distance10min)), 15min: \(formatDistance(distance15min))")
    }

    private func adjustZoomForSpeed(speed: CLLocationSpeed, coordinate: CLLocationCoordinate2D) {
        guard speed >= 0 else { return }

        // Only update zoom every 2 seconds to prevent excessive updates
        let now = Date()
        guard now.timeIntervalSince(lastSpeedZoomUpdate) > 2.0 else { return }
        lastSpeedZoomUpdate = now

        // Convert m/s to mph
        let mph = speed * 2.23694

        // Ford F-150 style altitude levels based on speed (higher altitude = zoomed out)
        let targetAltitude: CLLocationDistance
        if mph < 5 {
            // Stopped/very slow - close zoom to see street details
            targetAltitude = 300 // ~300 meters altitude (tight zoom)
        } else if mph < 25 {
            // City driving - moderate zoom
            targetAltitude = 500 // ~500 meters
        } else if mph < 45 {
            // Suburban/rural - wider view to see upcoming turns
            targetAltitude = 800 // ~800 meters
        } else if mph < 65 {
            // Highway speeds - zoom out to see far ahead
            targetAltitude = 1500 // ~1500 meters
        } else {
            // High speed highway - maximum zoom out
            targetAltitude = 2500 // ~2500 meters
        }

        // Only update if altitude changed significantly
        if abs(navigationCameraAltitude - targetAltitude) > 100 {
            navigationCameraAltitude = targetAltitude
            print("🔍 [ZOOM] Speed: \(Int(mph)) mph → Altitude: \(Int(targetAltitude))m")
            // The 3D camera will be updated via the binding in MapRepresentable
        }
    }

    private func showWaypointRemoveAlert(index: Int) {
        guard index < navigationManager.waypoints.count else { return }

        let alert = UIAlertController(
            title: "Remove Waypoint",
            message: "Remove waypoint \(index + 1)?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { _ in
            self.navigationManager.removeWaypoint(at: index)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(alert, animated: true)
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
