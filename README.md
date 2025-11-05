# Terralink Project

Integration of Tabula API with Rotorsync iOS app for field map management.

## Project Overview

**Purpose:** Download field maps and customer details from Tabula API and integrate them into the Rotorsync app.

**Components:**
1. **Backend API** (Node.js/Express) - Proxy server for Tabula API
2. **iOS App Integration** (Swift/SwiftUI) - Field maps management UI

## Architecture

```
┌─────────────────┐
│  Rotorsync App  │
│   (iOS/Swift)   │
└────────┬────────┘
         │
         │ HTTP/REST
         │
┌────────▼────────┐
│ Terralink       │
│ Backend API     │
│ (Node.js)       │
└────────┬────────┘
         │
         │ HTTP/REST
         │
┌────────▼────────┐
│  Tabula API     │
│ (test-api.      │
│  tracmap.com)   │
└─────────────────┘
```

## Features

### Backend Features
- Customer search API
- Field map retrieval (single and bulk)
- Field map export (GeoJSON, KML, etc.)
- Rate limiting and security
- Error handling and logging

### iOS App Features
- Customer search with multi-select
- Bulk field map import
- Apple Maps integration
- Field boundary visualization
- Interactive field selection
- Map type switching (Standard/Satellite)
- Field information display

## Project Structure

```
terralink-project/
├── backend/
│   ├── src/
│   │   ├── config/
│   │   │   └── tabula.js
│   │   ├── middleware/
│   │   │   └── errorHandler.js
│   │   ├── routes/
│   │   │   ├── customers.js
│   │   │   └── fieldMaps.js
│   │   ├── services/
│   │   │   └── tabulaService.js
│   │   └── index.js
│   ├── .env.example
│   ├── package.json
│   ├── deploy.sh
│   └── README.md
│
└── ios-app/
    ├── Models/
    │   └── FieldMapModels.swift
    ├── Services/
    │   └── TabulaAPIService.swift
    ├── Views/
    │   ├── FieldMapsManagementView.swift
    │   ├── CustomerSearchView.swift
    │   ├── FieldMapsViewModel.swift
    │   └── FieldMapsMapView.swift
    └── README.md
```

## Setup Instructions

### Prerequisites

**Backend:**
- Node.js v16+
- VM access: user@192.168.68.226

**iOS Development:**
- Xcode 14+
- macOS device: Aliyan@192.168.68.208
- Rotorsync app source code

**API Credentials:**
- Tabula API URL (default: https://test-api.tracmap.com)
- Tabula API Key (to be provided)
- Tabula API Secret (to be provided)

### Backend Setup

1. **Deploy to VM (192.168.68.226)**

   ```bash
   cd backend
   chmod +x deploy.sh
   ./deploy.sh
   ```

   Or manually:

   ```bash
   # SSH into VM
   ssh user@192.168.68.226

   # Create directory
   mkdir -p ~/terralink-backend
   cd ~/terralink-backend

   # Copy files (from local machine)
   # Then on VM:
   npm install
   cp .env.example .env
   nano .env  # Add Tabula API credentials

   # Start with PM2
   npm install -g pm2
   pm2 start src/index.js --name terralink-backend
   pm2 save
   pm2 startup
   ```

2. **Configure Environment Variables**

   Edit `.env` on the VM:
   ```env
   TABULA_API_URL=https://test-api.tracmap.com
   TABULA_API_KEY=your_api_key_here
   TABULA_API_SECRET=your_api_secret_here
   PORT=3000
   NODE_ENV=production
   ALLOWED_ORIGINS=*
   ```

3. **Test Backend**

   ```bash
   curl http://192.168.68.226:3000/health
   ```

### iOS App Integration

1. **SSH into Mac**

   ```bash
   ssh Aliyan@192.168.68.208
   ```

2. **Open Rotorsync Project**

   ```bash
   cd ~/Desktop/rotorsync-development
   open Rotorsync.xcodeproj
   ```

3. **Add Terralink Files**

   In Xcode:
   - Create groups: `Models/Terralink`, `Services/Terralink`, `Views/Terralink`
   - Add all Swift files from `ios-app/` directory

4. **Update Backend URL**

   In `TabulaAPIService.swift`:
   ```swift
   private let baseURL = "http://192.168.68.226:3000/api"
   ```

5. **Add Navigation**

   In your main view (e.g., `HomeView.swift`):
   ```swift
   NavigationLink(destination: FieldMapsManagementView()) {
       Label("Field Maps", systemImage: "map.fill")
   }
   ```

6. **Build and Test**

## GitHub Repository

**Repository:** https://github.com/austins05/Fork

**Deploy Key:**
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFoGK9qjoSr5SelzOtXlMNK6GbbhDq5svULEwx09Q3HH
```

### Pushing to GitHub

```bash
cd terralink-project
git init
git remote add origin git@github.com:austins05/Fork.git

# Add deploy key to GitHub first
# Settings > Deploy keys > Add deploy key

git add .
git commit -m "Initial Terralink implementation"
git push -u origin main
```

## API Documentation

### Backend API Endpoints

**Health Check:**
- `GET /health` - Server health status

**Customer Endpoints:**
- `GET /api/customers/search?q=query&limit=50` - Search customers
- `GET /api/customers/:id` - Get customer by ID

**Field Map Endpoints:**
- `GET /api/field-maps/customer/:customerId` - Get field maps for customer
- `POST /api/field-maps/bulk` - Get field maps for multiple customers
  ```json
  {
    "customerIds": ["id1", "id2", "id3"]
  }
  ```
- `GET /api/field-maps/:fieldId` - Get field map details
- `GET /api/field-maps/:fieldId/download?format=geojson` - Download field map

### Response Format

```json
{
  "success": true,
  "count": 10,
  "data": [...]
}
```

## Configuration Needed

⚠️ **Before the system is fully functional, you need:**

1. **Tabula API Credentials**
   - API URL (confirm: https://test-api.tracmap.com)
   - API Key
   - API Secret
   - Update in backend `.env` file

2. **API Documentation**
   - Exact endpoint paths
   - Authentication method (Bearer token, API key header, etc.)
   - Request/response formats
   - Field map data structure

3. **Network Configuration**
   - Ensure VM is accessible from Mac
   - Configure firewall rules if needed
   - Test connectivity between devices

## Testing

### Backend Tests

```bash
# Health check
curl http://192.168.68.226:3000/health

# Search customers (will fail without API credentials)
curl "http://192.168.68.226:3000/api/customers/search?q=test"

# Bulk field maps
curl -X POST http://192.168.68.226:3000/api/field-maps/bulk \
  -H "Content-Type: application/json" \
  -d '{"customerIds": ["id1", "id2"]}'
```

### iOS App Tests

1. Launch app on simulator or device
2. Navigate to Field Maps page
3. Search for customers
4. Select multiple customers
5. Click Import
6. View maps on Apple Maps

## Deployment Checklist

- [ ] Backend deployed to VM (192.168.68.226)
- [ ] Environment variables configured
- [ ] PM2 running backend service
- [ ] Backend accessible from network
- [ ] iOS files added to Xcode project
- [ ] Backend URL updated in iOS app
- [ ] Navigation link added to main view
- [ ] App builds successfully
- [ ] Tabula API credentials obtained
- [ ] API credentials configured in backend
- [ ] End-to-end test completed
- [ ] Code pushed to GitHub

## Support & Contact

- **Tabula API Support:** api@tabula.live
- **Tabula Web Portal:** https://app.tabula-online.com/

## License

[Add license information]
