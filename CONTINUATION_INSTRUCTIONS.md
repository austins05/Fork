# Tabula Integration - Continue From Here

## Context
Working on Rotorsync iOS app - integrated Tabula API for field map management. Backend deployed and running, iOS enhancements complete and building successfully.

## Current State
- ✅ Backend API: Running on 192.168.68.226:3000 (PM2)
- ✅ iOS App: Enhanced Field Maps tab, BUILD SUCCEEDED
- ✅ Documentation: Complete README created
- 📍 Next: Test features on device

## Key Information

### Backend
- **VM:** user@192.168.68.226 (password: `ncat2406zik!`)
- **Location:** `/home/user/terralink-backend`
- **Check status:** `ssh user@192.168.68.226 "pm2 status"`
- **View logs:** `ssh user@192.168.68.226 "pm2 logs terralink-backend"`

### iOS App
- **Mac:** Aliyan@192.168.68.208 (password: `aliyan`)
- **Project:** `~/Desktop/rotorsync-development/Rotorsync.xcodeproj`
- **Enhanced file:** `Terralink/Views/FieldMapsManagementView.swift`
- **Last build:** SUCCESS (2025-11-06)

### Features Implemented
1. "Last 20" quick filter button (user's specific request)
2. Stats dashboard (Maps, Acres, Customers, Avg Area)
3. Search bar for field maps
4. Quick filters (All, Last 20, Large Fields, Small Fields)
5. Sort options (Name, Area, Customer)
6. Enhanced visual design with color-coded indicators
7. Swipe to delete
8. Pull to refresh

## What to Do Next

### If Testing on Device:
```bash
# 1. Verify backend is running
curl http://192.168.68.226:3000/health

# 2. Open Xcode on Mac
ssh Aliyan@192.168.68.208
cd ~/Desktop/rotorsync-development
open Rotorsync.xcodeproj

# 3. In Xcode: Press ⌘R to run on iPad
# 4. Go to Field Maps tab
# 5. Test all features (search, filters, sort, stats)
```

### If Making Changes:
```bash
# Access Mac
ssh Aliyan@192.168.68.208

# Main files:
# - ~/Desktop/rotorsync-development/Rotorsync/Terralink/Views/FieldMapsManagementView.swift
# - ~/Desktop/rotorsync-development/Rotorsync/Terralink/Views/FieldMapsViewModel.swift
# - ~/Desktop/rotorsync-development/Rotorsync/Terralink/Models/FieldMapModels.swift

# Build from CLI:
cd ~/Desktop/rotorsync-development
xcodebuild -project Rotorsync.xcodeproj -scheme Rotorsync -sdk iphonesimulator build
```

### If Backend Issues:
```bash
# SSH to VM
ssh user@192.168.68.226

# Restart backend
pm2 restart terralink-backend

# Check logs
pm2 logs terralink-backend --lines 50
```

## Important Notes
- Component names were renamed to avoid conflicts: `FieldMapStatCard`, `FieldMapFilterButton`, `FieldMapSortSheet`
- Backend uses `token` header for Tabula API (not `Authorization: Bearer`)
- GeoJSON coordinates are [lon, lat], MapKit needs [lat, lon]
- Test data: Customer ID 5429 has 3 jobs (37537, 37468, 37469)

## Complete Documentation
Read these files for full details:
- **Mac:** `~/Desktop/TABULA_INTEGRATION_README.md`
- **Linux:** `/home/austin/terralink-project/TABULA_INTEGRATION_README.md`

## User's Original Request
> "Can you update the app with more features in the Field maps tab? Maybe a last 20 orders button?"

**Status:** ✅ COMPLETE - "Last 20" button implemented + 7 additional features

## Quick Commands Reference
```bash
# Test backend
curl http://192.168.68.226:3000/api/field-maps/customer/5429

# SSH to Mac
ssh Aliyan@192.168.68.208

# SSH to VM
ssh user@192.168.68.226

# PM2 status
pm2 status

# Build iOS
xcodebuild -project Rotorsync.xcodeproj -scheme Rotorsync build
```

---
**Last Updated:** 2025-11-06
**All systems:** ✅ OPERATIONAL
