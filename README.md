# Rotorsync

Agricultural aviation iPad application with real-time engine monitoring via USB.

## Features

### PeerTalk USB Engine Monitoring
- **Garmin G1000 style display** with alternating CHT/EGT vertical bar graphs
- Real-time temperature updates from Raspberry Pi via USB
- 12 temperature sensors (6 CHT + 6 EGT cylinders)
- Color-coded warning zones (normal/warning/danger)
- Live statistics: Max CHT, Max EGT, Average temps

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
The monitor displays alternating CHT and EGT bars for each cylinder in a horizontal scrollable view, with real-time updates.

### Temperature Thresholds
- **CHT**: 450°F danger, 420°F warning (250-500°F scale)
- **EGT**: 1650°F danger, 1550°F warning (1200-1700°F scale)

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
│   │       └── MonitorView.swift       # Garmin G1000 style display
│   ├── Map/                             # Field maps & pins
│   ├── FileManager/                     # File/folder management
│   └── Groups/                          # Collaboration
├── Services/
│   └── TemperatureService.swift         # PeerTalk integration
├── PeerTalk/                            # USB communication framework
│   ├── PTChannel.m
│   ├── PTProtocol.m
│   └── PTUSBHub.m
├── Terralink/                           # Tabula field maps
├── Core/
│   ├── Database/                        # Core Data
│   ├── Networking/                      # API & MQTT
│   └── Managers/                        # Location, etc.
└── Models/                              # Data models
```

## Temperature Monitor Technical Details

### TemperatureService.swift
- Singleton service managing PeerTalk connection
- Listens on port 2345 for incoming frames
- Decodes JSON temperature payload
- Publishes data via `@Published` properties

### MonitorView.swift
- Garmin G1000 inspired UI
- Alternating CHT/EGT bars for each cylinder
- SwiftUI + Combine for reactive updates
- Color-coded zones with gradient fills

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

---

**Generated with Claude Code**
https://claude.com/claude-code
