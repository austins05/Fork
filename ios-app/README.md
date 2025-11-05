# Terralink iOS Integration

iOS components for integrating Tabula field maps into the Rotorsync app.

## Overview

This integration adds a new Field Maps management feature to Rotorsync, allowing users to:
- Search for customers from Tabula API
- Select multiple customers
- Import their field maps
- Display field boundaries on Apple Maps
- Navigate and manage imported fields

## Components

### Models
- **FieldMapModels.swift** - Data models for customers, field maps, coordinates, and map annotations

### Services
- **TabulaAPIService.swift** - API client for communicating with the Terralink backend

### Views
- **FieldMapsManagementView.swift** - Main view for managing field maps
- **CustomerSearchView.swift** - Customer search with multi-select functionality
- **FieldMapsViewModel.swift** - ViewModel managing state and business logic
- **FieldMapsMapView.swift** - Apple Maps integration for displaying field boundaries

## Integration with Rotorsync

### Step 1: Add Files to Xcode Project

1. Open `Rotorsync.xcodeproj` in Xcode
2. Create new groups:
   - `Rotorsync/Models/Terralink`
   - `Rotorsync/Services/Terralink`
   - `Rotorsync/Views/Terralink`

3. Add the files to their respective groups:
   ```
   Models/Terralink/
     └─ FieldMapModels.swift

   Services/Terralink/
     └─ TabulaAPIService.swift

   Views/Terralink/
     ├─ FieldMapsManagementView.swift
     ├─ CustomerSearchView.swift
     ├─ FieldMapsViewModel.swift
     └─ FieldMapsMapView.swift
   ```

### Step 2: Update Backend URL

In `TabulaAPIService.swift`, update the `baseURL` property:

```swift
private let baseURL = "http://192.168.68.226:3000/api"
```

Change this to your actual backend server URL once deployed.

### Step 3: Add Navigation Link

In your main navigation view (likely `HomeView.swift` or `ContentView.swift`), add a navigation link:

```swift
NavigationLink(destination: FieldMapsManagementView()) {
    HStack {
        Image(systemName: "map.fill")
        Text("Field Maps")
    }
}
```

### Step 4: Update Info.plist

Add location permissions (if not already present):

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to show nearby fields on the map</string>
```

### Step 5: Add Dependencies (if needed)

The implementation uses only native SwiftUI and MapKit, so no additional dependencies are required.

## Configuration

### Backend Connection

The app connects to the Terralink backend at the URL specified in `TabulaAPIService.swift`. Make sure:

1. The backend is deployed and running on the VM
2. The URL is accessible from the iOS device
3. CORS is properly configured on the backend

### Testing

To test the integration:

1. Run the backend server on the VM
2. Build and run the Rotorsync app on a device or simulator
3. Navigate to the Field Maps page
4. Search for customers (this will fail until Tabula API credentials are configured)

## Features

### Customer Search
- Real-time search as you type
- Debounced API calls (500ms)
- Multi-select functionality
- Shows customer name, email, and address

### Field Maps Import
- Bulk import for multiple selected customers
- Progress indicator during import
- Error handling with user feedback
- Deduplication of existing maps

### Map Display
- Apple Maps integration
- Field boundary overlays with blue fill
- Interactive field selection
- Map type toggle (Standard/Satellite)
- Zoom to fit all fields or individual field
- Field information cards with details

## Data Models

### Customer
```swift
struct Customer {
    let id: String
    let name: String
    let email: String?
    let phone: String?
    let address: String?
}
```

### FieldMap
```swift
struct FieldMap {
    let id: String
    let customerId: String
    let name: String
    let description: String?
    let area: Double? // acres
    let boundaries: [Coordinate]
    let center: Coordinate?
    let metadata: FieldMapMetadata?
}
```

## API Endpoints Used

- `GET /api/customers/search?q=query` - Search customers
- `POST /api/field-maps/bulk` - Get field maps for multiple customers
- `GET /api/field-maps/:fieldId` - Get field map details

## Notes

- The current implementation assumes GeoJSON format for field boundaries
- Field areas are displayed in acres
- The app caches imported field maps locally (in-memory)
- For persistent storage, integrate with Core Data or existing persistence layer

## TODO

- [ ] Add persistent storage for imported field maps
- [ ] Implement field map export functionality
- [ ] Add offline support
- [ ] Integrate with existing Rotorsync navigation
- [ ] Add field activity tracking
- [ ] Implement field map updates/sync
