# Terralink Setup Guide

Step-by-step instructions to deploy and configure the Terralink system.

## Prerequisites Checklist

- [ ] Node.js installed on VM (192.168.68.226)
- [ ] Xcode installed on Mac (192.168.68.208)
- [ ] Access to both machines
- [ ] GitHub repository created: https://github.com/austins05/Fork
- [ ] Tabula API credentials obtained

## Part 1: GitHub Repository Setup

### 1.1 Add Deploy Key to GitHub

1. Go to https://github.com/austins05/Fork/settings/keys
2. Click "Add deploy key"
3. Title: `Terralink Deploy Key`
4. Key: Paste the public key:
   ```
   ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFoGK9qjoSr5SelzOtXlMNK6GbbhDq5svULEwx09Q3HH
   ```
5. ✅ Check "Allow write access"
6. Click "Add key"

### 1.2 Push Code to GitHub

**Option A: Push from Mac (192.168.68.208)**

```bash
# SSH into Mac
ssh Aliyan@192.168.68.208

# Copy project to Mac (if not already there)
# Or transfer the terralink-project folder

cd ~/Desktop
# If you transferred the folder here
cd terralink-project

# Configure git with the deploy key
git remote add origin git@github.com:austins05/Fork.git
GIT_SSH_COMMAND="ssh -i ~/.ssh/rotorsync_deploy_key" git push -u origin main
```

**Option B: Push from current machine**

If you have access to the private key:
```bash
cd ~/terralink-project
git remote add origin git@github.com:austins05/Fork.git
git push -u origin main
```

## Part 2: Backend Deployment

### 2.1 Verify VM Access

```bash
ssh user@192.168.68.226
# Password: ncat2406zik!
```

If authentication fails, verify:
- Username is correct
- Password is correct
- SSH service is running on VM
- Network connectivity

### 2.2 Install Node.js on VM (if not installed)

```bash
ssh user@192.168.68.226

# Check if Node.js is installed
node --version

# If not installed:
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify installation
node --version
npm --version
```

### 2.3 Deploy Backend

**Method 1: Using deploy script (from local machine)**

```bash
cd ~/terralink-project/backend
./deploy.sh
```

**Method 2: Manual deployment**

```bash
# From local machine, copy files to VM
cd ~/terralink-project/backend
scp -r package.json src/ .env.example README.md user@192.168.68.226:~/terralink-backend/

# SSH into VM
ssh user@192.168.68.226
cd ~/terralink-backend

# Install dependencies
npm install

# Configure environment
cp .env.example .env
nano .env
```

### 2.4 Configure Backend Environment

Edit `.env` file on VM:

```env
TABULA_API_URL=https://test-api.tracmap.com
TABULA_API_KEY=YOUR_ACTUAL_API_KEY_HERE
TABULA_API_SECRET=YOUR_ACTUAL_API_SECRET_HERE
PORT=3000
NODE_ENV=production
ALLOWED_ORIGINS=*
```

**Important:** Replace `YOUR_ACTUAL_API_KEY_HERE` and `YOUR_ACTUAL_API_SECRET_HERE` with actual Tabula credentials.

### 2.5 Start Backend Service

```bash
# Install PM2 process manager
sudo npm install -g pm2

# Start the service
pm2 start src/index.js --name terralink-backend

# Configure PM2 to start on system boot
pm2 save
pm2 startup

# Check status
pm2 status
pm2 logs terralink-backend
```

### 2.6 Test Backend

```bash
# From VM
curl http://localhost:3000/health

# From local network
curl http://192.168.68.226:3000/health
```

Expected response:
```json
{
  "status": "ok",
  "timestamp": "2025-11-05T...",
  "uptime": 123.45
}
```

### 2.7 Configure Firewall (if needed)

```bash
# If using UFW
sudo ufw allow 3000/tcp
sudo ufw reload

# If using firewalld
sudo firewall-cmd --permanent --add-port=3000/tcp
sudo firewall-cmd --reload
```

## Part 3: iOS App Integration

### 3.1 Access Mac

```bash
ssh Aliyan@192.168.68.208
# Password: aliyan
```

### 3.2 Copy iOS Files to Mac

Transfer the `ios-app` folder to the Mac:

```bash
# From local machine
scp -r ~/terralink-project/ios-app Aliyan@192.168.68.208:~/Desktop/
```

### 3.3 Open Rotorsync in Xcode

```bash
# On Mac
cd ~/Desktop/rotorsync-development
open Rotorsync.xcodeproj
```

### 3.4 Add Terralink Files to Project

In Xcode:

1. **Create folder structure:**
   - Right-click on `Rotorsync` group
   - New Group → `Terralink`
   - Inside `Terralink`, create groups:
     - `Models`
     - `Services`
     - `Views`

2. **Add files:**
   - Drag `FieldMapModels.swift` to `Terralink/Models`
   - Drag `TabulaAPIService.swift` to `Terralink/Services`
   - Drag all view files to `Terralink/Views`:
     - `FieldMapsManagementView.swift`
     - `CustomerSearchView.swift`
     - `FieldMapsViewModel.swift`
     - `FieldMapsMapView.swift`
   - Ensure "Copy items if needed" is checked
   - Ensure "Add to targets: Rotorsync" is checked

### 3.5 Configure Backend URL

In `TabulaAPIService.swift`, update line ~17:

```swift
private let baseURL = "http://192.168.68.226:3000/api"
```

Verify this matches your backend server address.

### 3.6 Add Navigation Link

In `HomeView.swift` (or your main navigation view), add:

```swift
NavigationLink(destination: FieldMapsManagementView()) {
    HStack {
        Image(systemName: "map.fill")
            .foregroundColor(.blue)
        VStack(alignment: .leading) {
            Text("Field Maps")
                .font(.headline)
            Text("Manage customer field maps")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    .padding()
}
```

### 3.7 Update Info.plist (if needed)

If location permissions aren't already configured:

1. Open `Info.plist`
2. Add key: `Privacy - Location When In Use Usage Description`
3. Value: `We need your location to show nearby fields on the map`

### 3.8 Build and Test

1. Select a simulator or connected device
2. Build the project (⌘B)
3. Run the app (⌘R)
4. Navigate to "Field Maps"

## Part 4: Tabula API Configuration

### 4.1 Update API Service (if endpoints differ)

Once you have the actual Tabula API documentation:

1. Edit `backend/src/services/tabulaService.js`
2. Update endpoint paths in methods:
   - `searchCustomers()` - Update line ~44
   - `getCustomer()` - Update line ~64
   - `getFieldMaps()` - Update line ~84
   - `getFieldMapDetails()` - Update line ~130
   - `downloadFieldMap()` - Update line ~150

3. Update authentication in interceptor (line ~27):
   ```javascript
   config.headers['Authorization'] = `Bearer ${this.apiKey}`;
   // Or whatever format Tabula requires
   ```

### 4.2 Restart Backend

```bash
ssh user@192.168.68.226
pm2 restart terralink-backend
pm2 logs terralink-backend
```

## Part 5: Testing

### 5.1 Backend Tests

```bash
# Health check
curl http://192.168.68.226:3000/health

# API info
curl http://192.168.68.226:3000/

# Search customers
curl "http://192.168.68.226:3000/api/customers/search?q=test"

# Bulk field maps
curl -X POST http://192.168.68.226:3000/api/field-maps/bulk \
  -H "Content-Type: application/json" \
  -d '{"customerIds": ["id1", "id2"]}'
```

### 5.2 iOS App Tests

1. Launch app on device/simulator
2. Navigate to "Field Maps"
3. Tap search icon
4. Enter customer name
5. Select one or more customers
6. Tap "Add"
7. Tap "Import Field Maps"
8. View imported maps in list
9. Tap "View on Map"
10. Interact with map:
    - Tap field boundaries
    - View field details
    - Toggle map type
    - Zoom to fit

### 5.3 End-to-End Test

Complete workflow:
1. Search: "John" → Find customers
2. Select: 3 customers
3. Import: Download their field maps
4. View: See maps on Apple Maps
5. Interact: Tap field, view details, zoom

## Troubleshooting

### Backend Issues

**Problem: Cannot connect to VM**
```bash
# Test connectivity
ping 192.168.68.226

# Check SSH service
ssh user@192.168.68.226 'systemctl status sshd'
```

**Problem: Backend not starting**
```bash
# Check logs
pm2 logs terralink-backend

# Check dependencies
cd ~/terralink-backend
npm install

# Manual start for debugging
node src/index.js
```

**Problem: API credentials not working**
- Verify credentials in `.env`
- Check Tabula API documentation
- Test credentials directly with curl
- Check authentication format in `tabulaService.js`

### iOS Issues

**Problem: Cannot connect to backend**
- Verify Mac can reach VM: `ping 192.168.68.226`
- Check firewall rules on VM
- Verify backend URL in `TabulaAPIService.swift`
- Try from Safari: `http://192.168.68.226:3000/health`

**Problem: Build errors**
- Check all files are added to target
- Verify import statements
- Clean build folder (⇧⌘K)
- Rebuild (⌘B)

**Problem: No search results**
- Check backend logs
- Verify API credentials
- Test backend directly with curl
- Check network connection

### Network Issues

**Problem: Devices cannot communicate**
```bash
# From Mac
ping 192.168.68.226

# From VM
ping 192.168.68.208

# Check if on same network
ip addr show
```

## Maintenance

### Update Backend
```bash
ssh user@192.168.68.226
cd ~/terralink-backend
git pull origin main
npm install
pm2 restart terralink-backend
```

### View Logs
```bash
# Backend logs
pm2 logs terralink-backend

# System logs
journalctl -u pm2-user.service -f
```

### Monitor Backend
```bash
# Status
pm2 status

# Monitor resources
pm2 monit
```

## Security Notes

- Change default passwords
- Use environment variables for secrets
- Enable HTTPS in production
- Configure proper CORS origins
- Implement authentication if needed
- Keep dependencies updated
- Regular security audits

## Next Steps

Once basic system is working:

1. [ ] Add persistent storage for field maps (Core Data)
2. [ ] Implement offline support
3. [ ] Add field map sync functionality
4. [ ] Integrate with existing Rotorsync features
5. [ ] Add analytics/tracking
6. [ ] Performance optimization
7. [ ] User documentation
8. [ ] Beta testing

## Support

- **Tabula API:** api@tabula.live
- **Documentation:** Check README.md files in each directory
- **Issues:** Report on GitHub
