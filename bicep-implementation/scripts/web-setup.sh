#!/bin/bash
# Web Tier Setup Script
# This script configures the web servers with nginx and basic health monitoring

set -e

# Update system packages
apt-get update -y

# Install nginx, monitoring tools, and Azure CLI
apt-get install -y nginx htop curl jq unzip

# Install Azure CLI for monitoring and management
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Configure nginx
cat > /etc/nginx/sites-available/default << 'EOF'
server {
listen 80;
listen 443 ssl default_server;
server_name _;

# Self-signed SSL certificate for demonstration
ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;

root /var/www/html;
index index.html index.htm;

# Health check endpoint for load balancer
location /health {
access_log off;
return 200 "healthy\n";
add_header Content-Type text/plain;
}

# Main application
location / {
try_files $uri $uri/ =404;
}

# Proxy to application tier (internal load balancer)
location /api/ {
proxy_pass http://10.0.2.4:8080/; # Internal LB IP will be dynamic
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
}
}
EOF

# Create a simple index page
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
<title>Azure Multi-Tier Application - Web Tier</title>
<style>
body { font-family: Arial, sans-serif; margin: 40px; }
.container { max-width: 800px; margin: 0 auto; }
.tier { background: #f0f8ff; padding: 20px; margin: 20px 0; border-radius: 5px; }
.status { color: #008000; font-weight: bold; }
</style>
</head>
<body>
<div class="container">
<h1>Azure Multi-Tier Application</h1>
<div class="tier">
<h2>Web Tier</h2>
<p><span class="status">Status:</span> Running</p>
<p><span class="status">Server:</span> <span id="hostname"></span></p>
<p><span class="status">Region:</span> ${tier} tier server</p>
</div>
<div class="tier">
<h2>Architecture Features</h2>
<ul>
<li>High Availability with Azure Load Balancer</li>
<li>Auto-scaling capabilities</li>
<li>Health monitoring</li>
<li>SSL/TLS termination</li>
<li>Disaster Recovery with Azure Site Recovery</li>
</ul>
</div>
</div>
<script>
document.getElementById('hostname').textContent = window.location.hostname;
</script>
</body>
</html>
EOF

# Enable and start nginx
systemctl enable nginx
systemctl start nginx

# Configure log rotation
cat > /etc/logrotate.d/webapp << 'EOF'
/var/log/nginx/*.log {
daily
missingok
rotate 52
compress
delaycompress
notifempty
create 644 www-data www-data
postrotate
if [ -f /var/run/nginx.pid ]; then
kill -USR1 `cat /var/run/nginx.pid`
fi
endscript
}
EOF

# Install and configure Azure Monitor agent (simplified)
# In production, use proper Azure Monitor integration
echo "Web tier ${tier} configuration completed at $(date)" > /var/log/setup.log

# Set up basic monitoring script
cat > /usr/local/bin/health-monitor.sh << 'EOF'
#!/bin/bash
# Simple health monitoring script
LOG_FILE="/var/log/health-monitor.log"
while true; do
if curl -f http://localhost/health > /dev/null 2>&1; then
echo "$(date): Health check passed" >> $LOG_FILE
else
echo "$(date): Health check failed" >> $LOG_FILE
systemctl restart nginx
fi
sleep 30
done
EOF

chmod +x /usr/local/bin/health-monitor.sh

# Create systemd service for health monitoring
cat > /etc/systemd/system/health-monitor.service << 'EOF'
[Unit]
Description=Application Health Monitor
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/health-monitor.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl enable health-monitor.service
systemctl start health-monitor.service

echo "Web tier setup completed successfully"