# Rotorsync

Agricultural aviation iPad application with real-time engine monitoring via USB.

## Features

### PeerTalk USB Engine Monitoring
- **Professional engine display** with vertical CHT/EGT bar graphs for all 6 cylinders
- **Real-time temperature updates** from Raspberry Pi via USB
- **Adaptive theming** - Light mode by default, dark mode when system is in dark mode
- **Color-coded warning zones** with smooth gradients:
  - CHT: Green (normal) → Amber (480-499°F) → Red (≥500°F)
  - EGT: Blue (normal) → Amber (1650-1679°F) → Red (≥1680°F)
- **Visual threshold indicators** - Red lines on bars at danger thresholds
- **Temperature difference monitoring**:
  - EGT MAX DIFF turns red when ≥100°F difference between cylinders
  - CHT MAX DIFF turns red when ≥70°F difference between cylinders
- **Map overlay** - Draggable, resizable temperature graph on map view
- **Live statistics**: Max CHT, Max EGT, cylinder count

### Temperature Display Features
- **Layout**: EGT value (top, blue) → Cylinder number → Side-by-side bars → CHT value (bottom, green)
- **Full-range scaling**: CHT 0-550°F, EGT 0-1800°F
- **Connection status**: Minimized banner when disconnected, data remains visible at 60% opacity
- **12 temperature sensors**: 6 CHT + 6 EGT cylinders
- **Horizontal scrolling** for comfortable viewing of all cylinders

### Map Temperature Overlay
- **Positioning**: Four preset corners (Top Left, Top Right, Bottom Left, Bottom Right)
- **Resizable**: Slider control (0.7x - 1.5x scale)
- **Draggable**: Move anywhere on screen via header
- **Toggleable**: On/off control in map settings
- **Status indicator**: Green dot when connected, orange when searching

### Field Management
- Import and display field maps from Tabula API
- Customer search with multi-select
- Bulk field map import
- Apple Maps integration with field boundary overlays
- Interactive field selection and details

### Pin & Group Management
- Drop custom pins on map
- Organize pins in folders and groups
- KML import/export
- Real-time collaboration via MQTT
- Share pins across devices

## Architecture

### iOS App (Swift/SwiftUI)
- **PeerTalk Integration**: USB communication with Raspberry Pi
- **Combine Framework**: Reactive data flow
- **SwiftUI Environment**: Adaptive color schemes
- **Core Data**: Local persistence
- **MQTT**: Real-time sync
- **MapKit**: Field and pin visualization

### Backend (Node.js/Express)
- Tabula API proxy for field maps
- Customer search endpoints
- Rate limiting and security

### Raspberry Pi (Python)
- SMTC thermocouple reading (I2C)
- PeerTalk frame transmission
- Port forwarding via iproxy

## PeerTalk Engine Monitor

### Display Layout
The monitor displays all 6 cylinders in a horizontal scrollable view with:
- **EGT temperature** (blue number at top)
- **Cylinder number** (centered in labeled box)
- **Dual bars** (CHT green on left, EGT blue on right)
- **CHT temperature** (green number at bottom)

### Temperature Thresholds & Scaling

#### CHT (Cylinder Head Temperature)
- **Scale**: 0-550°F (full range)
- **Warning**: 480°F (amber color)
- **Danger**: 500°F (red color + red threshold line)
- **MAX DIFF Alert**: Red indicator when cylinder spread ≥70°F

#### EGT (Exhaust Gas Temperature)
- **Scale**: 0-1800°F (full range)
- **Warning**: 1650°F (amber color)
- **Danger**: 1680°F (red color + red threshold line)
- **MAX DIFF Alert**: Red indicator when cylinder spread ≥100°F

### Visual Warning System
1. **Normal Operation**: Bars display in their base color (CHT green, EGT blue)
2. **Warning Zone**: Bars turn amber when approaching limits
3. **Danger Zone**: Bars turn red when exceeding thresholds
4. **Red Lines**: Horizontal indicator at danger threshold on each bar
5. **MAX DIFF**: White text on red background when cylinder spread exceeds limits

### PeerTalk Protocol
- **Frame Format**: version (UInt32), type (UInt32), tag (UInt32), payloadSize (UInt32)
- **Network Byte Order**: Big-endian for all header fields
- **Frame Type**: 100 for temperature data
- **Payload**: JSON with 6 CHT + 6 EGT readings

## Setup

### Prerequisites
- iOS 16.0+
- Xcode 15+
- Raspberry Pi with SMTC thermocouples
- Node.js 18+ (for backend)

### iOS App Installation

1. **Clone Repository**
   ```bash
   git clone https://github.com/austins05/Fork.git
   cd Fork
   ```

2. **Open in Xcode**
   ```bash
   open Rotorsync.xcodeproj
   ```

3. **Configure PeerTalk**
   - Ensure `Rotorsync/PeerTalk/` folder contains PeerTalk framework
   - Check bridging header: `Rotorsync/Rotorsync-Bridging-Header.h`

4. **Build & Run**
   - Select iPad as target device
   - Press ⌘R to build and deploy

### Raspberry Pi Setup

1. **Install Dependencies**
   ```bash
   sudo apt update
   sudo apt install -y libimobiledevice-utils usbmuxd python3-pip
   pip3 install smbus2
   ```

2. **Deploy Temperature Daemon**
   ```bash
   # Copy peertalk_temp_sender.py to /home/pi/
   python3 ~/peertalk_temp_sender.py
   ```

3. **Connect iPad via USB**
   - Plug iPad into Raspberry Pi USB port
   - On iPad: Trust this computer
   - Pi will automatically detect and connect

4. **Start iproxy**
   ```bash
   iproxy 2345 2345 &
   ```

### Backend API Setup

1. **Install Dependencies**
   ```bash
   cd backend
   npm install
   ```

2. **Configure Environment**
   ```bash
   cp .env.example .env
   # Edit .env with Tabula API credentials
   ```

3. **Deploy to VM**
   ```bash
   ./deploy.sh
   ```

## File Structure

```
Rotorsync/
├── Features/
│   ├── Monitor/
│   │   └── Views/
│   │       └── MonitorView.swift            # Professional engine display
│   ├── Map/
│   │   └── Views/
│   │       └── Components/
│   │           ├── TemperatureGraphOverlay.swift  # Map overlay
│   │           └── OverlaySettingsView.swift      # Overlay controls
│   ├── FileManager/                          # File/folder management
│   └── Groups/                               # Collaboration
├── Services/
│   └── TemperatureService.swift              # PeerTalk integration
├── PeerTalk/                                 # USB communication framework
│   ├── PTChannel.m
│   ├── PTProtocol.m
│   └── PTUSBHub.m
├── Terralink/                                # Tabula field maps
├── Core/
│   ├── Database/                             # Core Data
│   ├── Networking/                           # API & MQTT
│   └── Managers/                             # Location, etc.
└── Models/                                   # Data models
```

## Temperature Monitor Technical Details

### TemperatureService.swift
- Singleton service managing PeerTalk connection
- Listens on port 2345 for incoming frames
- Decodes JSON temperature payload
- Publishes data via `@Published` properties
- Connection status monitoring

### MonitorView.swift
- Professional engine monitor UI
- Adaptive light/dark theming via `@Environment(\.colorScheme)`
- EGT/CHT layout: number (top) → bars → number (bottom)
- SwiftUI + Combine for reactive updates
- Color-coded zones with gradient fills
- Red threshold lines at danger levels
- MAX DIFF indicators with conditional red highlighting

### TemperatureGraphOverlay.swift
- Compact temperature display for map view
- Draggable via header gesture
- Resizable via bottom-right handle
- Four position presets with smooth animations
- Size slider (0.7x to 1.5x)
- Same color scheme and scaling as main monitor

### Python Daemon (Raspberry Pi)
```python
# PeerTalk frame format
frame_header = struct.pack('>IIII',
    1,                    # version (PTProtocolVersion1)
    100,                  # type (temperature data)
    0,                    # tag
    len(payload_bytes))   # payloadSize

# JSON payload
{
  "cht": [385, 390, 382, 388, 391, 387],  # °F
  "egt": [1385, 1420, 1390, 1410, 1405, 1398],
  "timestamp": 1699216123.45,
  "unit": "F"
}
```

## Temperature Monitoring Best Practices

### Normal Operation
- CHT: 350-420°F typical cruise
- EGT: 1350-1550°F typical cruise
- MAX DIFF: <50°F for CHT, <75°F for EGT

### Warning Conditions
- **Amber Alert**: CHT 480-499°F or EGT 1650-1679°F
- **Action**: Reduce power, increase cooling

### Danger Conditions
- **Red Alert**: CHT ≥500°F or EGT ≥1680°F
- **Action**: Immediate power reduction, prepare for landing

### Cylinder Imbalance
- **CHT spread ≥70°F**: Possible cooling issue, fouled plug, or mixture imbalance
- **EGT spread ≥100°F**: Possible induction leak, fuel flow issue, or ignition problem

## Contributing

1. Fork the repository
2. Create feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Open Pull Request

## License

Proprietary - All Rights Reserved

## Support

For issues or questions, please open a GitHub issue.

## Changelog

### Latest Updates
- ✅ Adaptive light/dark theme support
- ✅ Temperature graph map overlay with drag/resize
- ✅ Updated temperature thresholds (CHT: 480/500°F, EGT: 1650/1680°F)
- ✅ Full-range temperature scaling (CHT: 0-550°F, EGT: 0-1800°F)
- ✅ Red threshold lines on temperature bars
- ✅ MAX DIFF indicators with alert thresholds
- ✅ Color scheme update (EGT blue, CHT green)
- ✅ Minimized connection error display
- ✅ Professional layout with numbers top and bottom

---

**Generated with Claude Code**
https://claude.com/claude-code
