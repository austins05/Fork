#!/bin/bash

# Terralink Backend Deployment Script
# Deploy to VM at 192.168.68.226

set -e  # Exit on error

echo "========================================"
echo "Terralink Backend Deployment"
echo "Target: 192.168.68.226"
echo "========================================"
echo ""

# Configuration
VM_HOST="192.168.68.226"
VM_USER="user"
REMOTE_DIR="/opt/terralink-backend"
LOCAL_DIR="/home/austin/terralink-project/backend"

echo "Step 1: Creating deployment archive..."
cd /home/austin/terralink-project
tar -czf backend.tar.gz backend/
echo "✓ Archive created: backend.tar.gz"
echo ""

echo "Step 2: Copying to VM..."
scp backend.tar.gz ${VM_USER}@${VM_HOST}:/tmp/
echo "✓ Files copied to VM"
echo ""

echo "Step 3: Deploying on VM..."
ssh ${VM_USER}@${VM_HOST} << 'ENDSSH'
set -e

echo "Creating directory..."
sudo mkdir -p /opt/terralink-backend
sudo chown $USER:$USER /opt/terralink-backend

echo "Extracting files..."
cd /opt/terralink-backend
tar -xzf /tmp/backend.tar.gz --strip-components=1
rm /tmp/backend.tar.gz

echo "Installing dependencies..."
cd /opt/terralink-backend
npm install --production

echo "Checking for PM2..."
if ! command -v pm2 &> /dev/null; then
    echo "Installing PM2..."
    sudo npm install -g pm2
fi

echo "Stopping existing service (if running)..."
pm2 stop terralink-backend || true
pm2 delete terralink-backend || true

echo "Starting service..."
cd /opt/terralink-backend
pm2 start src/index.js --name terralink-backend
pm2 save

echo "Setting up PM2 to start on boot..."
sudo pm2 startup systemd -u $USER --hp /home/$USER

echo "✓ Deployment complete!"
pm2 status
ENDSSH

echo ""
echo "========================================"
echo "Deployment Complete!"
echo "========================================"
echo ""
echo "Backend API is now running at:"
echo "  http://192.168.68.226:3000"
echo ""
echo "Health check:"
echo "  curl http://192.168.68.226:3000/health"
echo ""
echo "View logs:"
echo "  ssh ${VM_USER}@${VM_HOST}"
echo "  pm2 logs terralink-backend"
echo ""
