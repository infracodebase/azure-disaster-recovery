#!/bin/bash
# Application Tier Setup Script
# This script configures the application servers with a simple Node.js application

set -e

# Update system packages
apt-get update -y

# Install Node.js, npm, and monitoring tools
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
apt-get install -y nodejs htop curl jq unzip

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Create application directory
mkdir -p /opt/app
cd /opt/app

# Create package.json
cat > package.json << 'EOF'
{
"name": "azure-multitier-app",
"version": "1.0.0",
"description": "Azure multi-tier application - Application tier",
"main": "app.js",
"scripts": {
"start": "node app.js",
"test": "echo \"Error: no test specified\" && exit 1"
},
"dependencies": {
"express": "^4.18.2",
"mysql2": "^3.6.0"
},
"keywords": ["azure", "nodejs", "multitier"],
"author": "Azure Infrastructure Team",
"license": "MIT"
}
EOF

# Install dependencies
npm install

# Create the main application
cat > app.js << 'EOF'
const express = require('express');
const mysql = require('mysql2/promise');
const os = require('os');

const app = express();
const PORT = process.env.PORT || 8080;

// Middleware for parsing JSON
app.use(express.json());

// Health check endpoint for load balancer
app.get('/health', (req, res) => {
res.status(200).send('healthy');
});

// Root endpoint with server information
app.get('/', (req, res) => {
const serverInfo = {
message: 'Application Tier - Azure Multi-Tier Architecture',
server: os.hostname(),
platform: os.platform(),
uptime: process.uptime(),
memory: process.memoryUsage(),
timestamp: new Date().toISOString()
};
res.json(serverInfo);
});

// API endpoint for application data
app.get('/api/status', (req, res) => {
res.json({
status: 'running',
tier: 'application',
server: os.hostname(),
timestamp: new Date().toISOString(),
connections: 'active'
});
});

// Database connection test endpoint
app.get('/api/db-status', async (req, res) => {
try {
// In production, use proper connection pooling and environment variables
const connection = await mysql.createConnection({
host: '10.0.3.4', // Data tier internal IP (will be dynamic)
user: 'appuser',
password: 'AppPassword123!',
database: 'webapp',
connectTimeout: 5000,
acquireTimeout: 5000
});

const [rows] = await connection.execute('SELECT 1 as test');
await connection.end();

res.json({
database: 'connected',
status: 'healthy',
timestamp: new Date().toISOString()
});
} catch (error) {
res.status(500).json({
database: 'disconnected',
status: 'error',
error: error.message,
timestamp: new Date().toISOString()
});
}
});

// Error handling middleware
app.use((error, req, res, next) => {
console.error('Application error:', error);
res.status(500).json({
error: 'Internal server error',
timestamp: new Date().toISOString()
});
});

// Start the server
app.listen(PORT, '0.0.0.0', () => {
console.log('Application tier server running on port ' + PORT);
console.log('Server hostname: ' + os.hostname());
console.log('Process ID: ' + process.pid);
});

// Graceful shutdown handling
process.on('SIGTERM', () => {
console.log('Received SIGTERM, shutting down gracefully');
process.exit(0);
});

process.on('SIGINT', () => {
console.log('Received SIGINT, shutting down gracefully');
process.exit(0);
});
EOF

# Create systemd service for the application
cat > /etc/systemd/system/webapp.service << 'EOF'
[Unit]
Description=Azure Multi-Tier Web Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/app
ExecStart=/usr/bin/node app.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=PORT=8080

[Install]
WantedBy=multi-user.target
EOF

# Set up log rotation for application logs
cat > /etc/logrotate.d/webapp << 'EOF'
/var/log/webapp.log {
daily
missingok
rotate 30
compress
delaycompress
notifempty
create 644 root root
postrotate
systemctl reload webapp || true
endscript
}
EOF

# Enable and start the application service
systemctl daemon-reload
systemctl enable webapp.service
systemctl start webapp.service

# Install and configure monitoring
cat > /usr/local/bin/app-monitor.sh << 'EOF'
#!/bin/bash
# Application monitoring script
LOG_FILE="/var/log/app-monitor.log"
while true; do
if curl -f http://localhost:8080/health > /dev/null 2>&1; then
echo "$(date): Application health check passed" >> $LOG_FILE
else
echo "$(date): Application health check failed" >> $LOG_FILE
systemctl restart webapp.service
fi
sleep 30
done
EOF

chmod +x /usr/local/bin/app-monitor.sh

# Create systemd service for application monitoring
cat > /etc/systemd/system/app-monitor.service << 'EOF'
[Unit]
Description=Application Health Monitor
After=network.target webapp.service

[Service]
Type=simple
ExecStart=/usr/local/bin/app-monitor.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl enable app-monitor.service
systemctl start app-monitor.service

echo "Application tier ${tier} setup completed successfully at $(date)" > /var/log/setup.log
echo "Application tier setup completed successfully"