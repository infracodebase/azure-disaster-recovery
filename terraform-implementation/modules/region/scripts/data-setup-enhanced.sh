#!/bin/bash
# Enhanced Data Tier Setup Script with MySQL Replication
# This script configures the database servers with MySQL master-slave replication

set -e

# Get instance metadata for replication configuration
INSTANCE_METADATA=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance?api-version=2021-02-01")
INSTANCE_NAME=$(echo $INSTANCE_METADATA | jq -r '.compute.name')
REGION=$(echo $INSTANCE_METADATA | jq -r '.compute.location')

# Determine if this is master or slave based on VM name
if [[ $INSTANCE_NAME == *"-data-vm-1" ]]; then
    DB_ROLE="master"
    SERVER_ID=1
    echo "Configuring as MySQL MASTER server"
else
    DB_ROLE="slave"
    SERVER_ID=2
    echo "Configuring as MySQL SLAVE server"
fi

# Log configuration start
echo "Starting MySQL configuration for tier=${tier}, role=$DB_ROLE, server_id=$SERVER_ID at $(date)" > /var/log/mysql-setup.log

# Update system packages
apt-get update -y

# Install MySQL server and monitoring tools
export DEBIAN_FRONTEND=noninteractive
apt-get install -y mysql-server htop curl jq unzip

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Stop MySQL to configure replication
systemctl stop mysql

# Configure MySQL for replication
cat > /etc/mysql/mysql.conf.d/replication.cnf << EOF
[mysqld]
# Basic Configuration
bind-address = 0.0.0.0
port = 3306

# Security settings
local-infile = 0
symbolic-links = 0

# Performance tuning
innodb_buffer_pool_size = 1G
innodb_log_file_size = 256M
innodb_flush_log_at_trx_commit = 1
innodb_flush_method = O_DIRECT

# Replication configuration
server-id = $SERVER_ID
log-bin = mysql-bin
binlog_format = ROW
binlog_do_db = webapp
expire_logs_days = 7

# Master-specific settings
log-slave-updates = 1
read_only = $([ "$DB_ROLE" = "slave" ] && echo "1" || echo "0")

# Relay log configuration for slaves
$([ "$DB_ROLE" = "slave" ] && echo "relay-log = relay-bin" || echo "# Master - no relay log needed")
$([ "$DB_ROLE" = "slave" ] && echo "relay-log-index = relay-bin.index" || echo "# Master - no relay log index needed")

# GTID settings for better replication
gtid_mode = ON
enforce_gtid_consistency = ON

# Monitoring and logging
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 2
log_queries_not_using_indexes = 1
EOF

# Create MySQL error log directory
mkdir -p /var/log/mysql
chown mysql:mysql /var/log/mysql

# Start MySQL with new configuration
systemctl start mysql

# Wait for MySQL to be ready
until mysqladmin ping >/dev/null 2>&1; do
  echo "Waiting for MySQL to be ready..."
  sleep 2
done

# Set root password and secure installation
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'RootPassword123!';"

# Create application database and users
mysql -u root -pRootPassword123! << 'EOF'
CREATE DATABASE IF NOT EXISTS webapp;

-- Create application user with limited privileges
CREATE USER IF NOT EXISTS 'appuser'@'%' IDENTIFIED BY 'AppPassword123!';
GRANT SELECT, INSERT, UPDATE, DELETE ON webapp.* TO 'appuser'@'%';

-- Create monitoring user
CREATE USER IF NOT EXISTS 'monitor'@'localhost' IDENTIFIED BY 'MonitorPassword123!';
GRANT PROCESS, REPLICATION CLIENT ON *.* TO 'monitor'@'localhost';

-- Create replication user (for master)
CREATE USER IF NOT EXISTS 'replication'@'%' IDENTIFIED BY 'ReplicationPassword123!';
GRANT REPLICATION SLAVE ON *.* TO 'replication'@'%';

USE webapp;

-- Create sample tables
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_username (username),
    INDEX idx_email (email)
);

CREATE TABLE IF NOT EXISTS sessions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    session_token VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_session_token (session_token),
    INDEX idx_expires_at (expires_at),
    INDEX idx_user_id (user_id)
);

CREATE TABLE IF NOT EXISTS app_metrics (
    id INT AUTO_INCREMENT PRIMARY KEY,
    metric_name VARCHAR(100) NOT NULL,
    metric_value DECIMAL(10,2),
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_metric_name (metric_name),
    INDEX idx_recorded_at (recorded_at)
);

-- Create replication health table
CREATE TABLE IF NOT EXISTS replication_health (
    id INT AUTO_INCREMENT PRIMARY KEY,
    check_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    master_status VARCHAR(50),
    slave_status VARCHAR(50),
    lag_seconds INT DEFAULT 0
);

FLUSH PRIVILEGES;
EOF

# Configure replication based on role
if [ "$DB_ROLE" = "master" ]; then
    echo "Configuring MySQL Master..."

    # Get master status for slave configuration
    mysql -u root -pRootPassword123! -e "SHOW MASTER STATUS;" > /tmp/master_status.txt

    # Insert sample data on master only
    mysql -u root -pRootPassword123! webapp << 'EOF'
INSERT IGNORE INTO users (username, email) VALUES
('admin', 'admin@example.com'),
('testuser', 'test@example.com'),
('demouser', 'demo@example.com'),
('masteruser', 'master@example.com');

INSERT IGNORE INTO app_metrics (metric_name, metric_value) VALUES
('cpu_usage', 45.2),
('memory_usage', 78.5),
('disk_usage', 23.1),
('active_connections', 12),
('master_writes_per_second', 15.3);
EOF

    echo "Master configuration completed."

    # Create script to show master status
    cat > /usr/local/bin/show-master-status.sh << 'EOF'
#!/bin/bash
mysql -u root -pRootPassword123! -e "SHOW MASTER STATUS\G"
mysql -u root -pRootPassword123! -e "SHOW SLAVE HOSTS\G"
EOF
    chmod +x /usr/local/bin/show-master-status.sh

elif [ "$DB_ROLE" = "slave" ]; then
    echo "Configuring MySQL Slave..."

    # Wait for master to be available and get replication info
    MASTER_IP="10.0.3.4"  # This would be the master IP from load balancer

    # Wait for master to be ready
    echo "Waiting for master database at $MASTER_IP..."
    while ! nc -z $MASTER_IP 3306; do
        echo "Master not ready, waiting..."
        sleep 5
    done

    echo "Master is ready, configuring slave replication..."

    # Configure slave to replicate from master
    mysql -u root -pRootPassword123! << EOF
CHANGE MASTER TO
    MASTER_HOST='$MASTER_IP',
    MASTER_USER='replication',
    MASTER_PASSWORD='ReplicationPassword123!',
    MASTER_AUTO_POSITION=1;

START SLAVE;
EOF

    # Create script to show slave status
    cat > /usr/local/bin/show-slave-status.sh << 'EOF'
#!/bin/bash
mysql -u root -pRootPassword123! -e "SHOW SLAVE STATUS\G"
EOF
    chmod +x /usr/local/bin/show-slave-status.sh

    echo "Slave configuration completed."
fi

# Configure firewall if enabled
if command -v ufw >/dev/null 2>&1; then
    ufw allow from 10.0.0.0/8 to any port 3306
    # Allow replication traffic between database servers
    ufw allow from 10.0.3.0/24 to any port 3306
    ufw allow from 10.1.3.0/24 to any port 3306
fi

# Set up data directory on additional disk (if available)
if [ -e /dev/disk/azure/scsi1/lun0 ]; then
    echo "Configuring additional disk for MySQL data..."

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
    echo "Additional disk configuration completed."
fi

# Set up database backup script
cat > /usr/local/bin/db-backup.sh << 'EOF'
#!/bin/bash
# Database backup script
BACKUP_DIR="/var/backups/mysql"
DATE=$(date +%Y%m%d_%H%M%S)
ROLE_SUFFIX=$([ -f /tmp/mysql_role ] && cat /tmp/mysql_role || echo "unknown")
BACKUP_FILE="$BACKUP_DIR/webapp_$${ROLE_SUFFIX}_backup_$DATE.sql"

mkdir -p $BACKUP_DIR

# Create backup
if [ "$ROLE_SUFFIX" = "master" ]; then
    # Master backup with binary log position
    mysqldump -u root -pRootPassword123! --single-transaction --routines --triggers --master-data=2 webapp > $BACKUP_FILE
else
    # Slave backup
    mysqldump -u root -pRootPassword123! --single-transaction --routines --triggers webapp > $BACKUP_FILE
fi

# Compress backup
gzip $BACKUP_FILE

# Remove backups older than 7 days
find $BACKUP_DIR -name "*.sql.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_FILE.gz"
EOF

chmod +x /usr/local/bin/db-backup.sh

# Store role information for backup script
echo $DB_ROLE > /tmp/mysql_role

# Schedule daily backups at different times for master/slave
BACKUP_HOUR=$([ "$DB_ROLE" = "master" ] && echo "2" || echo "3")
cat > /etc/cron.d/mysql-backup << EOF
# Daily MySQL backup
0 $BACKUP_HOUR * * * root /usr/local/bin/db-backup.sh >> /var/log/mysql-backup.log 2>&1
EOF

# Set up enhanced database monitoring script
cat > /usr/local/bin/db-monitor.sh << EOF
#!/bin/bash
# Enhanced database monitoring script
LOG_FILE="/var/log/db-monitor.log"

while true; do
    # Check if MySQL is running
    if systemctl is-active --quiet mysql; then
        # Test database connection
        if mysql -u monitor -pMonitorPassword123! -e "SELECT 1" > /dev/null 2>&1; then
            echo "\$(date): Database health check passed" >> \$LOG_FILE

            # Check replication status
            if [ "$DB_ROLE" = "master" ]; then
                # Master monitoring
                SLAVE_COUNT=\$(mysql -u monitor -pMonitorPassword123! -e "SHOW SLAVE HOSTS" | wc -l)
                echo "\$(date): Master - Connected slaves: \$((SLAVE_COUNT-1))" >> \$LOG_FILE
            else
                # Slave monitoring
                SLAVE_STATUS=\$(mysql -u monitor -pMonitorPassword123! -e "SHOW SLAVE STATUS\G" | grep "Slave_SQL_Running:" | awk '{print \$2}')
                SLAVE_LAG=\$(mysql -u monitor -pMonitorPassword123! -e "SHOW SLAVE STATUS\G" | grep "Seconds_Behind_Master:" | awk '{print \$2}')
                echo "\$(date): Slave - SQL Running: \$SLAVE_STATUS, Lag: \$${SLAVE_LAG}s" >> \$LOG_FILE

                # Record replication health
                mysql -u monitor -pMonitorPassword123! webapp -e "INSERT INTO replication_health (slave_status, lag_seconds) VALUES ('\$SLAVE_STATUS', \$SLAVE_LAG)" 2>/dev/null || true
            fi
        else
            echo "\$(date): Database connection failed" >> \$LOG_FILE
        fi
    else
        echo "\$(date): MySQL service not running" >> \$LOG_FILE
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

/var/log/mysql-setup.log {
    weekly
    missingok
    rotate 4
    compress
    delaycompress
    notifempty
    create 644 root root
}
EOF

# Create replication health check script
cat > /usr/local/bin/check-replication.sh << 'EOF'
#!/bin/bash
# Replication health check script

if [ "$1" = "master" ]; then
    echo "=== MASTER STATUS ==="
    mysql -u root -pRootPassword123! -e "SHOW MASTER STATUS\G"
    echo ""
    echo "=== CONNECTED SLAVES ==="
    mysql -u root -pRootPassword123! -e "SHOW SLAVE HOSTS\G"
    echo ""
    echo "=== BINARY LOG STATUS ==="
    mysql -u root -pRootPassword123! -e "SHOW BINARY LOGS;"
elif [ "$1" = "slave" ]; then
    echo "=== SLAVE STATUS ==="
    mysql -u root -pRootPassword123! -e "SHOW SLAVE STATUS\G"
    echo ""
    echo "=== RECENT REPLICATION HEALTH ==="
    mysql -u root -pRootPassword123! webapp -e "SELECT * FROM replication_health ORDER BY check_time DESC LIMIT 10;"
else
    echo "Usage: $0 [master|slave]"
    echo "Current role: $(cat /tmp/mysql_role 2>/dev/null || echo 'unknown')"
fi
EOF

chmod +x /usr/local/bin/check-replication.sh

# Final status
echo "Data tier ${tier} (\$DB_ROLE) setup completed successfully at \$(date)" >> /var/log/mysql-setup.log
echo "Replication role: $DB_ROLE, Server ID: $SERVER_ID" >> /var/log/mysql-setup.log

# Test replication status
sleep 5
if [ "$DB_ROLE" = "slave" ]; then
    /usr/local/bin/check-replication.sh slave >> /var/log/mysql-setup.log
else
    /usr/local/bin/check-replication.sh master >> /var/log/mysql-setup.log
fi

echo "Enhanced data tier setup with replication completed successfully"