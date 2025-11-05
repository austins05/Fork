# Terralink - Quick Start

## 🚀 5-Minute Deploy Guide

### Prerequisites
- [ ] Tabula API credentials
- [ ] VM accessible (192.168.68.226)
- [ ] Mac accessible (192.168.68.208)

### Deploy Backend (5 minutes)

```bash
# 1. Add deploy key to GitHub
# Go to: https://github.com/austins05/Fork/settings/keys
# Add key: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFoGK9qjoSr5SelzOtXlMNK6GbbhDq5svULEwx09Q3HH
# ✅ Allow write access

# 2. SSH to VM
ssh user@192.168.68.226

# 3. Clone and setup
git clone git@github.com:austins05/Fork.git ~/terralink-backend
cd ~/terralink-backend/backend
npm install

# 4. Configure
cp .env.example .env
nano .env
# Add your Tabula API credentials

# 5. Start service
sudo npm install -g pm2
pm2 start src/index.js --name terralink
pm2 save

# 6. Test
curl http://localhost:3000/health
```

### Deploy iOS App (10 minutes)

```bash
# 1. SSH to Mac
ssh Aliyan@192.168.68.208

# 2. Clone repo
cd ~/Desktop
git clone git@github.com:austins05/Fork.git terralink

# 3. Open Xcode
cd rotorsync-development
open Rotorsync.xcodeproj

# 4. In Xcode:
# - Create group: Rotorsync/Terralink
# - Drag all files from ~/Desktop/terralink/ios-app/
# - Build (⌘B) and Run (⌘R)
```

### Configure API Credentials

**Backend .env file:**
```env
TABULA_API_URL=https://test-api.tracmap.com
TABULA_API_KEY=your_key_here
TABULA_API_SECRET=your_secret_here
PORT=3000
NODE_ENV=production
```

**iOS Backend URL** (TabulaAPIService.swift):
```swift
private let baseURL = "http://192.168.68.226:3000/api"
```

### Test End-to-End

1. Open Rotorsync app
2. Navigate to "Field Maps"
3. Tap search icon
4. Search for a customer
5. Select customer(s)
6. Tap "Import Field Maps"
7. View maps on Apple Maps

### Troubleshooting

**Backend won't start:**
```bash
pm2 logs terralink
npm install
node src/index.js  # Debug mode
```

**iOS can't connect:**
```bash
# Test from Mac
curl http://192.168.68.226:3000/health
ping 192.168.68.226
```

**No search results:**
- Check backend logs: `pm2 logs terralink`
- Verify API credentials in `.env`
- Test Tabula API directly

### Quick Commands

```bash
# Backend
pm2 status                    # Check status
pm2 logs terralink            # View logs
pm2 restart terralink         # Restart service

# Git
git pull origin main          # Update code
git push origin main          # Push changes

# Testing
curl http://192.168.68.226:3000/health                           # Health
curl "http://192.168.68.226:3000/api/customers/search?q=test"   # Search
```

### Support

📧 Tabula API: api@tabula.live
📚 Full docs: See SETUP_GUIDE.md
🐛 Issues: GitHub Issues

---

**Need detailed instructions?** → See `SETUP_GUIDE.md`
**Want architecture info?** → See `README.md`
**Check project status?** → See `PROJECT_SUMMARY.md`
