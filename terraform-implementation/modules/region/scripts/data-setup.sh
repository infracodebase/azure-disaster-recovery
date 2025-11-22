#!/bin/bash
# Data Tier Setup Script
# This script configures the database servers with MySQL

set -e

# Update system packages
apt-get update -y

# Install MySQL server and monitoring tools
export DEBIAN_FRONTEND=noninteractive
apt-get install -y mysql-server htop curl jq unzip

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Secure MySQL installation and configuration
mysql_secure_installation_script() {
    mysql -e "UPDATE mysql.user SET Password = PASSWORD('RootPassword123!') WHERE User = 'root'"
    mysql -e "DELETE FROM mysql.user WHERE User=''"
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
    mysql -e "DROP DATABASE IF EXISTS test"
    mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%'"
    mysql -e "FLUSH PRIVILEGES"
}

# Configure MySQL for multi-tier architecture
cat > /etc/mysql/mysql.conf.d/webapp.cnf << 'EOF'
[mysqld]
# Network configuration
bind-address = 0.0.0.0
port = 3306

# Security settings
local-infile = 0
symbolic-links = 0

# Performance tuning
innodb_buffer_pool_size = 1G
innodb_log_file_size = 256M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT

# Replication settings (for master-slave setup)
server-id = 1
log-bin = mysql-bin
binlog_format = mixed
expire_logs_days = 7

# Monitoring and logging
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 2
log_queries_not_using_indexes = 1
EOF

# Restart MySQL with new configuration
systemctl restart mysql

# Set root password and secure installation
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'RootPassword123!';"

# Create application database and user
mysql -u root -pRootPassword123! << 'EOF'
CREATE DATABASE IF NOT EXISTS webapp;

-- Create application user with limited privileges
CREATE USER IF NOT EXISTS 'appuser'@'%' IDENTIFIED BY 'AppPassword123!';
GRANT SELECT, INSERT, UPDATE, DELETE ON webapp.* TO 'appuser'@'%';

-- Create monitoring user
CREATE USER IF NOT EXISTS 'monitor'@'localhost' IDENTIFIED BY 'MonitorPassword123!';
GRANT PROCESS, REPLICATION CLIENT ON *.* TO 'monitor'@'localhost';

USE webapp;

-- Create sample tables
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sessions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    session_token VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id),
    INDEX idx_session_token (session_token),
    INDEX idx_expires_at (expires_at)
);

CREATE TABLE IF NOT EXISTS app_metrics (
    id INT AUTO_INCREMENT PRIMARY KEY,
    metric_name VARCHAR(100) NOT NULL,
    metric_value DECIMAL(10,2),
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_metric_name (metric_name),
    INDEX idx_recorded_at (recorded_at)
);

-- Insert sample data
INSERT IGNORE INTO users (username, email) VALUES
('admin', 'admin@example.com'),
('testuser', 'test@example.com'),
('demouser', 'demo@example.com');

INSERT IGNORE INTO app_metrics (metric_name, metric_value) VALUES
('cpu_usage', 45.2),
('memory_usage', 78.5),
('disk_usage', 23.1),
('active_connections', 12);

FLUSH PRIVILEGES;
EOF

# Configure firewall (if enabled)
if command -v ufw >/dev/null 2>&1; then
    ufw allow from 10.0.0.0/8 to any port 3306
fi

# Set up MySQL data directory on additional disk (if available)
if [ -e /dev/disk/azure/scsi1/lun0 ]; then
    # Format and mount additional disk
    parted /dev/disk/azure/scsi1/lun0 mklabel gpt
    parted -a opt /dev/disk/azure/scsi1/lun0 mkpart primary ext4 0% 100%
    mkfs.ext4 /dev/disk/azure/scsi1/lun0-part1

    # Create mount point and backup current data
    mkdir -p /mnt/mysql-data
    mount /dev/disk/azure/scsi1/lun0-part1 /mnt/mysql-data

    # Add to fstab for persistent mounting
    echo "/dev/disk/azure/scsi1/lun0-part1 /mnt/mysql-data ext4 defaults,nofail 0 2" >> /etc/fstab

    # Stop MySQL, copy data, and update configuration
    systemctl stop mysql
    cp -R /var/lib/mysql/* /mnt/mysql-data/
    chown -R mysql:mysql /mnt/mysql-data

    # Update MySQL data directory
    sed -i 's|datadir.*|datadir = /mnt/mysql-data|' /etc/mysql/mysql.conf.d/mysqld.cnf

    # Update AppArmor profile if present
    if [ -f /etc/apparmor.d/usr.sbin.mysqld ]; then
        sed -i '/\/var\/lib\/mysql\//a\ \ /mnt/mysql-data/ r,' /etc/apparmor.d/usr.sbin.mysqld
        sed -i '/\/var\/lib\/mysql\//a\ \ /mnt/mysql-data/** rwk,' /etc/apparmor.d/usr.sbin.mysqld
        systemctl reload apparmor
    fi

    systemctl start mysql
fi

# Set up database backup script
cat > /usr/local/bin/db-backup.sh << 'EOF'
#!/bin/bash
# Database backup script
BACKUP_DIR="/var/backups/mysql"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/webapp_backup_$DATE.sql"

mkdir -p $BACKUP_DIR

# Create backup
mysqldump -u root -pRootPassword123! --single-transaction --routines --triggers webapp > $BACKUP_FILE

# Compress backup
gzip $BACKUP_FILE

# Remove backups older than 7 days
find $BACKUP_DIR -name "*.sql.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_FILE.gz"
EOF

chmod +x /usr/local/bin/db-backup.sh

# Schedule daily backups
cat > /etc/cron.d/mysql-backup << 'EOF'
# Daily MySQL backup at 2 AM
0 2 * * * root /usr/local/bin/db-backup.sh >> /var/log/mysql-backup.log 2>&1
EOF

# Set up database monitoring script
cat > /usr/local/bin/db-monitor.sh << 'EOF'
#!/bin/bash
# Database monitoring script
LOG_FILE="/var/log/db-monitor.log"

while true; do
    # Check if MySQL is running
    if systemctl is-active --quiet mysql; then
        # Test database connection
        if mysql -u monitor -pMonitorPassword123! -e "SELECT 1" > /dev/null 2>&1; then
            echo "$(date): Database health check passed" >> $LOG_FILE
        else
            echo "$(date): Database connection failed" >> $LOG_FILE
        fi
    else
        echo "$(date): MySQL service not running" >> $LOG_FILE
        systemctl restart mysql
    fi
    sleep 60
done
EOF

chmod +x /usr/local/bin/db-monitor.sh

# Create systemd service for database monitoring
cat > /etc/systemd/system/db-monitor.service << 'EOF'
[Unit]
Description=Database Health Monitor
After=mysql.service

[Service]
Type=simple
ExecStart=/usr/local/bin/db-monitor.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl enable db-monitor.service
systemctl start db-monitor.service

# Configure log rotation
cat > /etc/logrotate.d/mysql-custom << 'EOF'
/var/log/mysql-backup.log {
    weekly
    missingok
    rotate 12
    compress
    delaycompress
    notifempty
    create 644 root root
}

/var/log/db-monitor.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 root root
}
EOF

echo "Data tier ${tier} setup completed successfully at $(date)" > /var/log/setup.log
echo "Data tier setup completed successfully"