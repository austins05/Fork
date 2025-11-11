const express = require('express');
const router = express.Router();
const tabulaService = require('../services/tabulaService');

/**
 * Get sync status
 * GET /api/monitor/sync/status
 */
router.get('/sync/status', (req, res) => {
  try {
    const stats = tabulaService.getCacheStats();
    const now = Date.now();

    // Calculate overall sync status
    const customers = Object.keys(stats);
    const syncStatus = customers.map(customerId => {
      const customerStats = stats[customerId];
      const needsSync = customerStats.expiresInSeconds <= 0;

      return {
        customerId,
        totalJobs: customerStats.totalJobs,
        lastSyncDate: customerStats.lastSyncDate,
        lastSyncAgeSeconds: customerStats.lastSyncAgeSeconds,
        needsSync,
        status: needsSync ? 'expired' : 'fresh'
      };
    });

    res.json({
      success: true,
      timestamp: new Date().toISOString(),
      customers: syncStatus,
      totalCustomers: customers.length
    });
  } catch (error) {
    console.error('Get sync status error:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

/**
 * Manually trigger sync (clear cache and force fresh fetch)
 * POST /api/monitor/sync
 * Optional body: { customerId: "5429" } to sync specific customer
 */
router.post('/sync', async (req, res) => {
  try {
    const { customerId } = req.body || {};

    console.log('🔄 Manual sync triggered', customerId ? `for customer ${customerId}` : 'for all customers');

    // Clear cache
    tabulaService.clearCache(customerId);

    // Trigger fresh fetch
    let result;
    if (customerId) {
      // Sync specific customer
      const fieldMaps = await tabulaService.getFieldMaps(customerId);
      result = {
        customerId,
        jobsFetched: fieldMaps.length,
        syncedAt: new Date().toISOString()
      };
    } else {
      // Sync all cached customers
      const stats = tabulaService.getCacheStats();
      const customerIds = Object.keys(stats);

      if (customerIds.length === 0) {
        // No customers in cache, sync default customer
        const defaultCustomerId = '5429';
        const fieldMaps = await tabulaService.getFieldMaps(defaultCustomerId);
        result = {
          customers: [defaultCustomerId],
          totalJobsFetched: fieldMaps.length,
          syncedAt: new Date().toISOString()
        };
      } else {
        // Sync all customers that were in cache
        const syncResults = await Promise.allSettled(
          customerIds.map(id => tabulaService.getFieldMaps(id))
        );

        const totalJobs = syncResults
          .filter(r => r.status === 'fulfilled')
          .reduce((sum, r) => sum + r.value.length, 0);

        result = {
          customers: customerIds,
          totalJobsFetched: totalJobs,
          syncedAt: new Date().toISOString()
        };
      }
    }

    console.log('✅ Sync completed:', result);

    res.json({
      success: true,
      message: 'Sync completed successfully',
      data: result
    });
  } catch (error) {
    console.error('Sync error:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

/**
 * View all stats (includes sync info and cache details)
 * GET /api/monitor/stats
 */
router.get('/stats', (req, res) => {
  try {
    const cacheStats = tabulaService.getCacheStats();

    // Calculate summary statistics
    const customers = Object.keys(cacheStats);
    const totalJobs = customers.reduce((sum, id) => sum + cacheStats[id].totalJobs, 0);
    const totalCachedDetails = customers.reduce((sum, id) => sum + cacheStats[id].cachedDetailsCount, 0);

    res.json({
      success: true,
      timestamp: new Date().toISOString(),
      summary: {
        totalCustomers: customers.length,
        totalJobs,
        totalCachedDetails
      },
      customers: cacheStats
    });
  } catch (error) {
    console.error('Get stats error:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

module.exports = router;
