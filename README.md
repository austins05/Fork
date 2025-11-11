## Features

### 🚁 Helicopter Spray Line Visualization [NEW v2.0]
- **Actual Flight Path Display**: Shows individual helicopter spray lines (LineString geometry)
  - Spray line features per completed job
  - Real-time visualization of actual flight paths
  - Rendered as MKPolyline overlays on field boundaries
- **Automatic Color Contrast**: Spray lines automatically contrast with field background
  - Dark fields (luminance < 0.5) → White spray lines
  - Light fields (luminance ≥ 0.5) → Black spray lines
  - WCAG luminance formula for optimal visibility
- **Backend Integration**:
  - `/api/field-maps/:id/geometry?type=worked-detailed` endpoint
  - Returns GeoJSON FeatureCollection with LineString features
  - Each feature represents one spray pass
- **Intelligent Rendering**:
  - LineString coordinates properly decoded and displayed
  - 3px line width for clear visibility
  - Overlays field boundary polygons
  - Automatic refresh support

## Spray Line Visualization Details

### Overview
Helicopter spray lines show the actual flight paths taken during aerial application. Each completed job displays 53 individual spray line features as LineString geometry overlaying the field boundaries.

### Technical Implementation

#### Backend Endpoint
```
GET /api/field-maps/:fieldId/geometry?type=worked-detailed
```

Returns GeoJSON FeatureCollection with LineString features showing actual helicopter flight paths.

#### iOS Models (TabulaJobModels.swift)
Supports both Polygon (field boundaries) and LineString (spray lines) geometry types with custom Codable implementation.

#### Map Rendering (MapRepresentable.swift)
- **Polyline Creation**: Each spray line → MKPolyline overlay
- **Auto-Contrast**: Calculates field color luminance using WCAG formula: `0.2126×R + 0.7152×G + 0.0722×B`
- **Smart Colors**: Returns white for dark backgrounds, black for light backgrounds
- **Rendering**: 3px stroke width with contrasting color

### Usage

#### Importing Fields with Spray Lines
1. Navigate to **Terralink** tab
2. Search and select customer (e.g., customer 5429)
3. Select jobs with status "Complete" (37468, 37469)
4. Tap "Import Selected to Map"
5. Switch to **Map** tab → Spray lines appear automatically

#### Viewing Spray Lines
- **Field Boundary**: Colored polygon (40% opacity)
- **Spray Lines**: Contrasting lines overlaying field
  - White lines on dark fields
  - Black lines on light fields
- **Details**: Tap field to see job information

#### Refreshing Data
1. Tap refresh button in Terralink tab
2. Clears all imported fields
3. Re-import to fetch latest geometry
4. New spray lines load automatically

### 🌡️ PeerTalk USB Engine Monitoring
- **Garmin G1000-style display** with alternating CHT/EGT vertical bar graphs
- Real-time temperature updates from Raspberry Pi via USB connection
- 12 temperature sensors (6 CHT + 6 EGT cylinders)
- Color-coded warning zones (normal/warning/danger)
- Live statistics: Max CHT, Max EGT, Average temperatures

### 🗺️ Tabula Field Management Integration
- **Customer Search**: Multi-select customer search with bulk import
- **Field Maps**: Import and display field maps from Tabula API
- **Job Management**: View job details, status, and order information
- **Apple Maps Integration**: Field boundary visualization
- **Backend Proxy**: Secure Node.js backend at 192.168.68.226:3000
- **Source Tracking**: Distinguish between Tabula and MPZ Field Mapper fields

### 🎨 Field Color Integration [STABLE v1.0]
- **Color-Coded Fields**: Imported fields display with Tracmap-assigned colors
  - Supported colors: Red, Orange, Yellow, Green, Teal, Blue, Purple, Pink, Gray
  - Automatic color name to hex conversion
  - Fields render with 40% transparency for visibility
- **Color-Matched Pins**: Field pins automatically match polygon colors
  - Map icon for all configured fields
  - Instant visual identification on crowded maps
- **Zebra Stripe Fallback**: Unconfigured fields display distinctive pattern
  - Black & yellow diagonal stripes on polygon
  - Zebra-striped pin with map icon
  - Immediate identification of fields needing configuration
- **Production Status**: Fully tested, stable, and ready for use

### 📍 Pin & Group Management
- Drop custom pins on map with icons and notes
- Organize pins in folders and groups
- KML import/export support
- Real-time collaboration via MQTT
- Share pins across devices and teams

## Architecture
## Architecture
