# Field Maps Caching System

## Overview

The backend now implements Tabula's **recommended polling pattern** with intelligent caching that dramatically reduces API calls to the Tracmap API from **1 + N requests** (where N is the number of jobs) down to **0-1 requests** for unchanged data.

## How It Works

### Before Caching
- **Every request**: Fetch all jobs (1 request) + Fetch details for each job (N requests) = **11 requests for 10 jobs**
- **Total API load**: 11 requests every time

### After Caching (Tabula Polling Pattern)
- **First request**: Fetch all modified jobs in last 90 days (1 request) + Fetch details (N requests) = **11 requests**
- **Subsequent requests with no changes**: Fetch modified jobs since last sync (1 request) + 0 results = **1 request total**
- **Subsequent requests with 2 changes**: Fetch modified jobs (1 request) + Fetch details for 2 jobs (2 requests) = **3 requests**

### Key Innovation: `from_date` Parameter
Following Tabula's documentation, we use the `from_date` parameter with `include_deleted=true`:
```
GET /accounts/{id}/jobs?include_deleted=true&from_date={epoch_timestamp}
```

This returns **only jobs modified since the specified date**, not the entire job list!

## Cache Strategy (Tabula Recommended Pattern)

### Polling with from_date
1. **First sync**: Query with `from_date` = 90 days ago to get all recent jobs
2. **Subsequent syncs**: Query with `from_date` = last sync time - 5 minutes (overlap)
3. **5-minute overlap**: Recommended by Tabula to avoid missing changes due to timing issues
4. **Merge strategy**: Modified jobs are merged into cached full job list
5. **Deleted jobs**: Automatically removed from cache when detected

### Intelligent Detail Fetching
The system only fetches full job details when:
- Job is new (not in cache)
- Job's `modified_date` has changed
- Cache has expired (5 minutes)

### Cache Lifetime
- **Expiry**: 5 minutes (configurable via `this.cacheExpiry`)
- **Overlap**: 5 minutes (configurable via `this.fromDateOverlap`)
- **Scope**: Per customer ID
- **Storage**: In-memory (resets on server restart)

### Example Scenario
```
Request 1 (no cache):
  📡 Polling for changes since 2024-01-01 (90 days ago)
  📦 Got 10 modified jobs from Tracmap
  🔄 Fetching details for 10 jobs (0 already cached)
  ✅ Cache updated: 10 total jobs
  → Makes 11 total requests

Request 2 (30 seconds later, no changes):
  📡 Polling for changes since 2024-03-31T15:30:00Z
  📦 Got 0 modified jobs from Tracmap
  ✅ No changes detected, using cached data
  → Makes 1 total request (91% reduction!)

Request 3 (30 seconds later, 1 job updated):
  📡 Polling for changes since 2024-03-31T15:30:30Z
  📦 Got 1 modified job from Tracmap
  🔄 Fetching details for 1 job (0 already cached)
  ✅ Cache updated: 10 total jobs
  → Makes 2 total requests (82% reduction!)

Request 4 (10 minutes later, no changes, cache expired):
  📡 Polling for changes since 2024-03-31T15:35:00Z
  📦 Got 0 modified jobs from Tracmap
  ✅ No changes detected, using cached data
  → Makes 1 total request (cache refreshed)
```

## API Endpoints

### Get Cache Statistics
```bash
GET /api/field-maps/cache/stats

Response:
{
  "success": true,
  "data": {
    "5429": {
      "totalJobs": 10,
      "cachedDetailsCount": 10,
      "cacheAgeSeconds": 45,
      "expiresInSeconds": 255,
      "lastSyncDate": "2024-03-31T15:30:45.123Z",
      "lastSyncAgeSeconds": 45
    }
  }
}
```

### Clear Cache
```bash
# Clear all cache
DELETE /api/field-maps/cache/clear

# Clear cache for specific customer
DELETE /api/field-maps/cache/clear?customerId=5429

Response:
{
  "success": true,
  "message": "Cache cleared for customer 5429"
}
```

## Benefits

### 1. Reduced API Calls
- **90%+ reduction** in API calls for unchanged data
- Avoids hitting rate limits
- Faster response times

### 2. Smart Updates
- Still gets fresh data when jobs change
- Automatically detects new jobs
- No stale data issues

### 3. Better Performance
- Cached responses return in milliseconds
- Reduced network latency
- Lower load on Tracmap servers

## Technical Implementation

### Cache Structure
```javascript
{
  'customerId': {
    timestamp: 1699876543210,  // When cache was last updated
    jobDetailsCache: {
      '37646': { /* full job details */ },
      '37644': { /* full job details */ },
      ...
    }
  }
}
```

### Code Location
- **Service**: `/src/services/tabulaService.js`
  - Lines 29-33: Cache initialization
  - Lines 109-203: Cached getFieldMaps() method
  - Lines 318-348: Cache management methods

- **Routes**: `/src/routes/fieldMaps.js`
  - Lines 177-219: Cache management endpoints

## Configuration

### Adjust Cache Expiry
Edit `/src/services/tabulaService.js`:
```javascript
this.cacheExpiry = 5 * 60 * 1000; // 5 minutes (default)
// Change to:
this.cacheExpiry = 10 * 60 * 1000; // 10 minutes
```

### Disable Caching (not recommended)
Set cache expiry to 0:
```javascript
this.cacheExpiry = 0; // Always fetch fresh data
```

## Monitoring

### Check Cache Status
```bash
# View cache statistics
curl http://192.168.68.226:3000/api/field-maps/cache/stats

# Monitor backend logs for cache messages
tail -f /tmp/backend_cached.log | grep "🔄"
```

### Cache Hit Rate
Watch for messages like:
```
🔄 Cache status: 0 jobs need updates (10 from cache)  ← 100% cache hit
🔄 Cache status: 2 jobs need updates (8 from cache)   ← 80% cache hit
🔄 Cache status: 10 jobs need updates (0 from cache)  ← 0% cache hit (first request)
```

## Future Enhancements

### Recommended: Tabula WebHooks (Section 2.4)
**From Tabula Documentation:**
> "Tabula exposes a WebHooks interface which can be used to register for notifications upon job completion or status changes. Where possible, this will typically be a more appropriate solution than continuously polling for changes."

**Benefits of WebHooks over Polling:**
- Real-time updates (no polling delay)
- Zero API requests when no changes
- Server pushes changes to us
- More efficient for both systems

**Implementation Plan:**
1. Register webhook endpoint with Tabula
2. Receive push notifications on job changes
3. Update cache immediately when notified
4. Keep polling as fallback for missed webhooks

### Other Possible Improvements
1. **Persistent Storage**: Use Redis for cache that survives restarts
2. **Preemptive Refresh**: Refresh cache before expiry for frequently accessed data
3. **Geometry Caching**: Cache field geometry data (currently not cached)
4. **Compression**: Compress cached data to reduce memory usage
5. **LRU Eviction**: Automatically remove least recently used customer caches

### Monitoring Dashboard
Could add real-time cache metrics:
- Total requests vs cached requests
- Cache hit ratio
- Memory usage
- Average response time

## Troubleshooting

### Cache Not Working
1. Check if cache is expired: `GET /api/field-maps/cache/stats`
2. Clear and rebuild: `DELETE /api/field-maps/cache/clear`
3. Check server logs for cache messages

### Stale Data
- Cache automatically refreshes after 5 minutes
- Manually clear: `DELETE /api/field-maps/cache/clear?customerId=5429`
- Jobs with changed `modified_date` are auto-updated

### High Memory Usage
- Cache stores full job details in memory
- Clears automatically after 5 minutes of inactivity
- Restart server to clear all caches
