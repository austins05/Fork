# Rotorsync

Professional agricultural aviation iPad application featuring real-time engine monitoring via USB and comprehensive field management with Tabula API integration.

## Features

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

### 📍 Pin & Group Management
- Drop custom pins on map with icons and notes
- Organize pins in folders and groups
- KML import/export support
- Real-time collaboration via MQTT
- Share pins across devices and teams

## Architecture

### iOS App (Swift/SwiftUI)
- **PeerTalk Integration**: USB communication with Raspberry Pi
- **Tabula Integration**: Field map management via backend proxy
- **Combine Framework**: Reactive data flow
- **Core Data**: Local persistence for pins and folders
- **MQTT**: Real-time synchronization
- **MapKit**: Field boundary and pin visualization

### Backend API (Node.js/Express)
- **Location**: 192.168.68.226:3000
- **Tabula API Proxy**: Customer search, field map retrieval
- **Endpoints**: 
  - `/health` - Health check
  - `/api/customers/search` - Customer search
  - `/api/field-maps/customer/:id` - Get field maps
  - `/api/field-maps/bulk` - Bulk field map retrieval
  - `/api/field-maps/:id/download` - GeoJSON geometry download
- **Security**: Rate limiting, CORS, error handling
- **Process Management**: PM2 for production deployment

### Raspberry Pi (Python)
- SMTC thermocouple reading via I2C
- PeerTalk frame transmission to iPad
- Port forwarding via iproxy

## Tabula Integration Details

### Architecture Flow
```
iOS App (Rotorsync) → Backend API (192.168.68.226:3000) → Tabula API (test-api.tracmap.com)
```

### iOS Components

#### Models (`Rotorsync/Terralink/Models/`)
- **FieldMapModels.swift**: Customer and FieldMap models
  - `Customer`: Customer data with ID, name, contact info
  - `FieldMap`: Job data (id, name, customer, area, status, orderNumber, etc.)
  - Response models for API communication

#### Services (`Rotorsync/Terralink/Services/`)
- **TabulaAPIService.swift**: API communication layer
  - Singleton pattern for shared instance
  - Customer search
  - Field map retrieval (single and bulk)
  - GeoJSON geometry fetching
  - Error handling and logging

- **SharedFieldStorage.swift**: Field persistence
  - Track field source (Tabula vs MPZ)
  - UserDefaults persistence
  - Duplicate prevention

#### Views (`Rotorsync/Terralink/Views/`)
- **FieldMapsManagementView.swift**: Main field management UI
  - Customer selection chips
  - Field map list with status indicators
  - Import functionality

- **CustomerSearchView.swift**: Customer search interface
  - Real-time search
  - Multi-select support
  - Integration with FieldMapsViewModel

- **FieldMapPreviewView.swift**: Individual field preview
  - Field details display
  - Geometry visualization
  - Action buttons

- **FieldMapsMapView.swift**: Map visualization
  - Apple Maps integration
  - Field boundary overlays (requires geometry)
  - Interactive field selection

- **FieldMapsViewModel.swift**: Business logic
  - Customer and field map management
  - API communication
  - State management

### Backend Components (`backend/`)

#### Configuration
- **src/config/tabula.js**: Tabula API configuration
  - Base URL: https://test-api.tracmap.com/v1
  - Token-based authentication
  - Environment variable management

#### Services
- **src/services/tabulaService.js**: Tabula API integration
  - Customer search
  - Job listing by customer
  - GeoJSON geometry retrieval
  - Error handling and logging

#### Routes
- **src/routes/customers.js**: Customer endpoints
  - Search with pagination
  - Customer details

- **src/routes/fieldMaps.js**: Field map endpoints
  - Single customer field maps
  - Bulk retrieval
  - Geometry download

#### Middleware
- **src/middleware/errorHandler.js**: Centralized error handling
- Rate limiting: 100 requests per 15 minutes per IP

## Temperature Monitor Technical Details

### Display Specifications
- **CHT Thresholds**: 450°F danger, 420°F warning (250-500°F scale)
- **EGT Thresholds**: 1650°F danger, 1550°F warning (1200-1700°F scale)
- **Update Rate**: Real-time via USB
- **Color Coding**: Green (normal), Yellow (warning), Red (danger)

### PeerTalk Protocol
- **Port**: 2345
- **Frame Format**: Header + JSON payload
- **Network Byte Order**: Big-endian
- **Payload Structure**: 
  ```json
  {
    "cht": [temp1, temp2, temp3, temp4, temp5, temp6],
    "egt": [temp1, temp2, temp3, temp4, temp5, temp6]
  }
  ```

## Setup

### Prerequisites
- iOS 17.6+
- Xcode 15+
- Raspberry Pi with SMTC thermocouples (for engine monitoring)
- Node.js 18+ (for backend)
- macOS for iOS development

### iOS App Installation

1. **Clone Repository**
   ```bash
   git clone git@github.com:austins05/Fork.git
   cd Fork
   ```

2. **Open in Xcode**
   ```bash
   open Rotorsync.xcodeproj
   ```

3. **Configure Signing**
   - Select Rotorsync target
   - Update bundle identifier
   - Configure signing team

4. **Build & Run**
   - Select iPad as target device
   - Press ⌘R to build and deploy

### Backend API Setup

1. **SSH to Backend VM**
   ```bash
   ssh user@192.168.68.226
   ```

2. **Navigate to Backend Directory**
   ```bash
   cd ~/terralink-backend
   ```

3. **Install Dependencies**
   ```bash
   npm install
   ```

4. **Configure Environment**
   ```bash
   cp .env.example .env
   nano .env
   ```
   
   Update with Tabula API credentials:
   ```
   TABULA_API_URL=https://test-api.tracmap.com/v1
   TABULA_API_KEY=your_api_key
   TABULA_API_SECRET=your_api_secret
   PORT=3000
   NODE_ENV=production
   ```

5. **Start with PM2**
   ```bash
   pm2 start src/index.js --name terralink-backend
   pm2 save
   pm2 startup
   ```

6. **Verify Deployment**
   ```bash
   curl http://192.168.68.226:3000/health
   pm2 status
   pm2 logs terralink-backend
   ```

### Raspberry Pi Setup (Engine Monitoring)

1. **Install Dependencies**
   ```bash
   sudo apt-get update
   sudo apt-get install python3-smbus python3-pip libimobiledevice-utils
   pip3 install smbus2
   ```

2. **Deploy Temperature Daemon**
   ```bash
   sudo cp temperature_daemon.py /usr/local/bin/
   sudo chmod +x /usr/local/bin/temperature_daemon.py
   ```

3. **Connect iPad**
   - Plug iPad into Raspberry Pi USB port
   - On iPad: Trust this computer
   - Pi will automatically detect and connect

4. **Start iproxy**
   ```bash
   iproxy 2345 2345 &
   ```

## File Structure

```
Rotorsync/
├── Rotorsync.xcodeproj         # Xcode project
├── Rotorsync/
│   ├── Core/                   # Core services
│   │   ├── Managers/          # Location, MQTT managers
│   │   ├── Networking/        # API services
│   │   └── Database/          # Core Data models
│   ├── Features/              # Feature modules
│   │   ├── Map/              # Map view and utilities
│   │   ├── Pins/             # Pin management
│   │   ├── Groups/           # Group functionality
│   │   ├── Monitor/          # Engine temperature monitoring
│   │   └── Authentication/   # Login/auth
│   ├── Terralink/            # Tabula integration
│   │   ├── Models/           # Data models
│   │   ├── Services/         # API services
│   │   └── Views/            # UI components
│   ├── Models/               # Shared models
│   ├── Services/             # Shared services
│   └── RotorsyncApp.swift    # App entry point
├── backend/                   # Node.js backend (deployed to VM)
│   ├── src/
│   │   ├── config/           # Configuration
│   │   ├── services/         # Tabula API service
│   │   ├── routes/           # API routes
│   │   ├── middleware/       # Express middleware
│   │   └── index.js          # Server entry point
│   ├── .env.example          # Environment template
│   └── package.json          # Dependencies
└── raspberry-pi/             # Raspberry Pi scripts
    └── temperature_daemon.py # Temperature sensor daemon
```

## API Endpoints

### Backend API (192.168.68.226:3000)

#### Health Check
```
GET /health
```

#### Customer Search
```
GET /api/customers/search?q=searchTerm&limit=50
```

#### Field Maps
```
GET /api/field-maps/customer/:customerId
POST /api/field-maps/bulk
  Body: { "customerIds": ["id1", "id2"] }
GET /api/field-maps/:fieldId/download?format=geojson
```

## Testing

### Backend Testing
```bash
# Health check
curl http://192.168.68.226:3000/health

# Search customers
curl "http://192.168.68.226:3000/api/customers/search?q=test"

# Get field maps
curl http://192.168.68.226:3000/api/field-maps/customer/5429
```

### iOS Testing
1. Open Rotorsync on iPad
2. Navigate to Field Maps tab
3. Search for customers
4. Select and import field maps
5. Verify maps appear on the map view

## Development

### Adding New Features
1. Create feature branch
2. Implement changes
3. Test thoroughly
4. Update documentation
5. Create pull request

### Code Style
- Swift: Follow Swift API Design Guidelines
- Node.js: ESLint with standard configuration
- Comments: Use /// for documentation

## Troubleshooting

### Backend Issues
```bash
# Check PM2 status
pm2 status

# View logs
pm2 logs terralink-backend --lines 100

# Restart service
pm2 restart terralink-backend
```

### iOS Build Issues
- Clean build folder: Shift + ⌘K
- Clear derived data: ~/Library/Developer/Xcode/DerivedData
- Verify provisioning profiles

### Temperature Monitor Not Connecting
- Verify iPad is trusted on Raspberry Pi
- Check iproxy is running: `ps aux | grep iproxy`
- Verify PeerTalk port: `lsof -i :2345`

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

**Built with Claude Code**  
https://claude.com/claude-code
