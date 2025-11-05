# Deploy Terralink Backend to VM

## Quick Deploy Instructions

Since SSH from my end is having password authentication issues, here are the exact commands to run on the VM.

### Step 1: SSH to VM

From your machine:
```bash
ssh user@192.168.68.226
# Password: ncat2406zik!
```

### Step 2: Run This Complete Script

Once on the VM, copy and paste this entire script:

```bash
#!/bin/bash
set -e

echo "╔════════════════════════════════════════════════╗"
echo "║   Terralink Backend Deployment                ║"
echo "╔════════════════════════════════════════════════╗"
echo ""

# Create directory
cd ~
mkdir -p terralink-backend/src/{routes,services,config,middleware}
cd terralink-backend

# Create package.json
cat > package.json << 'PKGJSON'
{
  "name": "terralink-backend",
  "version": "1.0.0",
  "description": "Backend API for Terralink",
  "main": "src/index.js",
  "scripts": {
    "start": "node src/index.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.0",
    "dotenv": "^16.3.1",
    "cors": "^2.8.5",
    "helmet": "^7.1.0",
    "morgan": "^1.10.0",
    "express-rate-limit": "^7.1.5"
  }
}
PKGJSON

# Create .env
cat > .env << 'ENVFILE'
TABULA_API_URL=https://test-api.tracmap.com
TABULA_API_KEY=your_api_key_here
TABULA_API_SECRET=your_api_secret_here
PORT=3000
NODE_ENV=production
ALLOWED_ORIGINS=*
ENVFILE

# Create config
cat > src/config/tabula.js << 'CONFIGFILE'
require('dotenv').config();

module.exports = {
  apiUrl: process.env.TABULA_API_URL || 'https://test-api.tracmap.com',
  apiKey: process.env.TABULA_API_KEY,
  apiSecret: process.env.TABULA_API_SECRET,
  timeout: 30000,
  retryAttempts: 3
};
CONFIGFILE

# Create tabula service
cat > src/services/tabulaService.js << 'SERVICEFILE'
const axios = require('axios');
const config = require('../config/tabula');

class TabulaService {
  constructor() {
    this.client = axios.create({
      baseURL: config.apiUrl,
      timeout: config.timeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      }
    });

    this.client.interceptors.request.use(
      (config) => {
        if (this.apiKey && this.apiSecret) {
          config.headers['Authorization'] = \`Bearer \${this.apiKey}\`;
        }
        return config;
      },
      (error) => Promise.reject(error)
    );
  }

  async searchCustomers(searchQuery, limit = 50) {
    try {
      const response = await this.client.get('/customers/search', {
        params: { q: searchQuery, limit: limit }
      });
      return response.data;
    } catch (error) {
      console.error('Error searching customers:', error.message);
      throw this.handleError(error);
    }
  }

  async getCustomer(customerId) {
    try {
      const response = await this.client.get(\`/customers/\${customerId}\`);
      return response.data;
    } catch (error) {
      console.error('Error fetching customer:', error.message);
      throw this.handleError(error);
    }
  }

  async getFieldMaps(customerId) {
    try {
      const response = await this.client.get(\`/customers/\${customerId}/fields\`);
      return response.data;
    } catch (error) {
      console.error('Error fetching field maps:', error.message);
      throw this.handleError(error);
    }
  }

  async getFieldMapsForMultipleCustomers(customerIds) {
    try {
      const promises = customerIds.map(id => this.getFieldMaps(id));
      const results = await Promise.allSettled(promises);
      const fieldMaps = [];
      results.forEach((result, index) => {
        if (result.status === 'fulfilled') {
          fieldMaps.push(...result.value);
        } else {
          console.error(\`Failed to fetch field maps for customer \${customerIds[index]}:\`, result.reason);
        }
      });
      return fieldMaps;
    } catch (error) {
      console.error('Error fetching multiple field maps:', error.message);
      throw this.handleError(error);
    }
  }

  async getFieldMapDetails(fieldId) {
    try {
      const response = await this.client.get(\`/fields/\${fieldId}\`);
      return response.data;
    } catch (error) {
      console.error('Error fetching field map details:', error.message);
      throw this.handleError(error);
    }
  }

  async downloadFieldMap(fieldId, format = 'geojson') {
    try {
      const response = await this.client.get(\`/fields/\${fieldId}/export\`, {
        params: { format }
      });
      return response.data;
    } catch (error) {
      console.error('Error downloading field map:', error.message);
      throw this.handleError(error);
    }
  }

  handleError(error) {
    if (error.response) {
      return new Error(\`Tabula API Error (\${error.response.status}): \${error.response.data.message || error.response.statusText}\`);
    } else if (error.request) {
      return new Error('Tabula API Error: No response from server');
    } else {
      return new Error(\`Tabula API Error: \${error.message}\`);
    }
  }
}

module.exports = new TabulaService();
SERVICEFILE

# Create customer routes
cat > src/routes/customers.js << 'CUSTOMERROUTES'
const express = require('express');
const router = express.Router();
const tabulaService = require('../services/tabulaService');

router.get('/search', async (req, res) => {
  try {
    const { q, limit } = req.query;
    if (!q || q.trim().length < 2) {
      return res.status(400).json({ error: 'Search query must be at least 2 characters' });
    }
    const customers = await tabulaService.searchCustomers(q, parseInt(limit) || 50);
    res.json({ success: true, count: customers.length, data: customers });
  } catch (error) {
    console.error('Customer search error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const customer = await tabulaService.getCustomer(id);
    res.json({ success: true, data: customer });
  } catch (error) {
    console.error('Get customer error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

module.exports = router;
CUSTOMERROUTES

# Create field maps routes
cat > src/routes/fieldMaps.js << 'FIELDMAPROUTES'
const express = require('express');
const router = express.Router();
const tabulaService = require('../services/tabulaService');

router.get('/customer/:customerId', async (req, res) => {
  try {
    const { customerId } = req.params;
    const fieldMaps = await tabulaService.getFieldMaps(customerId);
    res.json({ success: true, count: fieldMaps.length, data: fieldMaps });
  } catch (error) {
    console.error('Get field maps error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

router.post('/bulk', async (req, res) => {
  try {
    const { customerIds } = req.body;
    if (!Array.isArray(customerIds) || customerIds.length === 0) {
      return res.status(400).json({ success: false, error: 'customerIds must be a non-empty array' });
    }
    if (customerIds.length > 100) {
      return res.status(400).json({ success: false, error: 'Maximum 100 customers allowed per request' });
    }
    const fieldMaps = await tabulaService.getFieldMapsForMultipleCustomers(customerIds);
    res.json({ success: true, count: fieldMaps.length, customersProcessed: customerIds.length, data: fieldMaps });
  } catch (error) {
    console.error('Bulk field maps error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

router.get('/:fieldId', async (req, res) => {
  try {
    const { fieldId } = req.params;
    const fieldMap = await tabulaService.getFieldMapDetails(fieldId);
    res.json({ success: true, data: fieldMap });
  } catch (error) {
    console.error('Get field map details error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

router.get('/:fieldId/download', async (req, res) => {
  try {
    const { fieldId } = req.params;
    const { format } = req.query;
    const mapData = await tabulaService.downloadFieldMap(fieldId, format || 'geojson');
    res.json({ success: true, format: format || 'geojson', data: mapData });
  } catch (error) {
    console.error('Download field map error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

module.exports = router;
FIELDMAPROUTES

# Create error handler
cat > src/middleware/errorHandler.js << 'ERRORHANDLER'
const errorHandler = (err, req, res, next) => {
  console.error('Error:', err);
  const statusCode = err.statusCode || 500;
  const message = err.message || 'Internal Server Error';
  res.status(statusCode).json({
    success: false,
    error: message,
    ...(process.env.NODE_ENV === 'development' && { stack: err.stack })
  });
};

module.exports = errorHandler;
ERRORHANDLER

# Create main server file
cat > src/index.js << 'INDEXFILE'
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');

const customerRoutes = require('./routes/customers');
const fieldMapRoutes = require('./routes/fieldMaps');
const errorHandler = require('./middleware/errorHandler');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(helmet());
app.use(cors({ origin: process.env.ALLOWED_ORIGINS?.split(',') || '*', methods: ['GET', 'POST', 'PUT', 'DELETE'], allowedHeaders: ['Content-Type', 'Authorization'] }));

const limiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 100, message: 'Too many requests from this IP, please try again later.' });
app.use('/api/', limiter);

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(morgan('combined'));

app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString(), uptime: process.uptime() });
});

app.use('/api/customers', customerRoutes);
app.use('/api/field-maps', fieldMapRoutes);

app.get('/', (req, res) => {
  res.json({ name: 'Terralink Backend API', version: '1.0.0', description: 'Backend API for Tabula integration with Rotorsync', endpoints: { health: '/health', customers: { search: 'GET /api/customers/search?q=searchTerm', getById: 'GET /api/customers/:id' }, fieldMaps: { byCustomer: 'GET /api/field-maps/customer/:customerId', bulk: 'POST /api/field-maps/bulk', details: 'GET /api/field-maps/:fieldId', download: 'GET /api/field-maps/:fieldId/download?format=geojson' } } });
});

app.use((req, res) => {
  res.status(404).json({ success: false, error: 'Endpoint not found' });
});

app.use(errorHandler);

app.listen(PORT, () => {
  console.log(\`🚀 Terralink Backend API running on port \${PORT}\`);
  console.log(\`📝 Environment: \${process.env.NODE_ENV || 'development'}\`);
  console.log(\`🔗 API URL: http://localhost:\${PORT}\`);
});

process.on('SIGTERM', () => {
  console.log('SIGTERM signal received: closing HTTP server');
  server.close(() => { console.log('HTTP server closed'); });
});
INDEXFILE

# Install dependencies
echo ""
echo "📦 Installing dependencies..."
npm install

# Check if PM2 is installed
if ! command -v pm2 &> /dev/null; then
    echo "📥 Installing PM2..."
    sudo npm install -g pm2
fi

# Start the service
echo "🚀 Starting backend..."
pm2 delete terralink-backend 2>/dev/null || true
pm2 start src/index.js --name terralink-backend
pm2 save
pm2 startup

echo ""
echo "╔════════════════════════════════════════════════╗"
echo "║           ✅ DEPLOYMENT COMPLETE!              ║"
echo "╔════════════════════════════════════════════════╗"
echo ""
echo "Backend running at: http://192.168.68.226:3000"
echo ""
echo "Test it:"
echo "  curl http://localhost:3000/health"
echo ""
echo "⚠️  IMPORTANT: Update Tabula API credentials in .env"
echo "  nano ~/terralink-backend/.env"
echo ""
echo "Then restart:"
echo "  pm2 restart terralink-backend"
echo ""
```

### Step 3: Test the Backend

```bash
# Test health endpoint
curl http://localhost:3000/health

# Should return:
# {"status":"ok","timestamp":"...","uptime":...}
```

### Step 4: Configure Tabula API Credentials

```bash
cd ~/terralink-backend
nano .env
```

Update these lines:
```env
TABULA_API_KEY=your_actual_api_key
TABULA_API_SECRET=your_actual_api_secret
```

Save and restart:
```bash
pm2 restart terralink-backend
```

### Step 5: Verify

```bash
# Check status
pm2 status

# View logs
pm2 logs terralink-backend

# Test from iOS app (should now work!)
```

## Done!

Backend will be running at: `http://192.168.68.226:3000`
