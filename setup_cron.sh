#!/bin/bash

# Setup cron jobs for 24/7 VPS operation of the Binance Trading Bot
# This script sets up automatic startup, monitoring, and log maintenance
# Uses global Python packages (no virtual environment)

# Get the absolute path of the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Define colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Setting up cron jobs for 24/7 VPS operation...${NC}"

# Create necessary scripts

# Create log rotation script
cat > "${SCRIPT_DIR}/rotate_logs.sh" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
LOG_DIR="${SCRIPT_DIR}/logs"
MAX_SIZE_MB=100
MAX_LOG_FILES=10

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Function to rotate a specific log file
rotate_log() {
    local log_file="$1"
    local base_name=$(basename "$log_file")
    
    # Check if file exists and is larger than MAX_SIZE_MB
    if [ -f "$log_file" ]; then
        size_kb=$(du -k "$log_file" | cut -f1)
        size_mb=$((size_kb / 1024))
        
        if [ $size_mb -ge $MAX_SIZE_MB ]; then
            echo "Rotating $log_file (Size: ${size_mb}MB)"
            timestamp=$(date +"%Y%m%d_%H%M%S")
            mv "$log_file" "${LOG_DIR}/${base_name}.${timestamp}"
            
            # Compress the rotated log
            gzip "${LOG_DIR}/${base_name}.${timestamp}"
            
            # Keep only MAX_LOG_FILES most recent logs
            ls -t "${LOG_DIR}/${base_name}."* | tail -n +$((MAX_LOG_FILES+1)) | xargs -r rm
            
            # Create new empty log file
            touch "$log_file"
        fi
    fi
}

# Rotate main logs
rotate_log "${LOG_DIR}/bot_console.log"
rotate_log "${LOG_DIR}/watchdog.log"
rotate_log "${LOG_DIR}/watchdog_console.log"

# Rotate trading logs
find "${LOG_DIR}" -name "trading_bot_*.log" -type f | while read log_file; do
    rotate_log "$log_file"
done

echo "Log rotation completed at $(date)" >> "${LOG_DIR}/log_rotation.log"
EOF
chmod +x "${SCRIPT_DIR}/rotate_logs.sh"

# Create a health check script
cat > "${SCRIPT_DIR}/health_check.sh" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
LOG_DIR="${SCRIPT_DIR}/logs"
ALERT_LOG="${LOG_DIR}/alerts.log"

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Function to log with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$ALERT_LOG"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if bot and watchdog are running
BOT_RUNNING=false
WATCHDOG_RUNNING=false

if [ -f "${SCRIPT_DIR}/bot.pid" ]; then
    BOT_PID=$(cat "${SCRIPT_DIR}/bot.pid")
    if ps -p $BOT_PID > /dev/null; then
        BOT_RUNNING=true
    fi
else
    # Try to find the bot process even without pid file
    BOT_PID=$(pgrep -f "python3 ${SCRIPT_DIR}/main.py")
    if [ -n "$BOT_PID" ]; then
        BOT_RUNNING=true
        # Save the found PID
        echo $BOT_PID > "${SCRIPT_DIR}/bot.pid"
    fi
fi

if [ -f "${SCRIPT_DIR}/watchdog.pid" ]; then
    WATCHDOG_PID=$(cat "${SCRIPT_DIR}/watchdog.pid")
    if ps -p $WATCHDOG_PID > /dev/null; then
        WATCHDOG_RUNNING=true
    fi
else
    # Try to find the watchdog process even without pid file
    WATCHDOG_PID=$(pgrep -f "${SCRIPT_DIR}/watchdog.sh")
    if [ -n "$WATCHDOG_PID" ]; then
        WATCHDOG_RUNNING=true
        # Save the found PID
        echo $WATCHDOG_PID > "${SCRIPT_DIR}/watchdog.pid"
    fi
fi

# Check if there are problems
if [ "$BOT_RUNNING" = false ] && [ "$WATCHDOG_RUNNING" = false ]; then
    log_message "CRITICAL: Both bot and watchdog are not running. Attempting to restart..."
    "${SCRIPT_DIR}/run_bot.sh" >> "${LOG_DIR}/cron_health_check.log" 2>&1
elif [ "$BOT_RUNNING" = false ]; then
    log_message "WARNING: Bot is not running but watchdog is active. Watchdog should restart it."
elif [ "$WATCHDOG_RUNNING" = false ]; then
    log_message "WARNING: Watchdog is not running. Restarting watchdog..."
    nohup "${SCRIPT_DIR}/watchdog.sh" > "${SCRIPT_DIR}/logs/watchdog_console.log" 2>&1 &
    WATCHDOG_PID=$!
    echo $WATCHDOG_PID > "${SCRIPT_DIR}/watchdog.pid"
    log_message "Watchdog restarted with PID ${WATCHDOG_PID}"
fi

# Check system resources
MEM_FREE=$(free -m | awk '/^Mem:/ {print $4}')
if [ $MEM_FREE -lt 200 ]; then
    log_message "WARNING: Low memory: ${MEM_FREE}MB free"
fi

DISK_FREE=$(df -m / | awk 'NR==2 {print $4}')
if [ $DISK_FREE -lt 1000 ]; then
    log_message "WARNING: Low disk space: ${DISK_FREE}MB free"
fi

# Check for frequent restarts by analyzing watchdog log
if [ -f "${LOG_DIR}/watchdog.log" ]; then
    RESTART_COUNT=$(grep -c "Restarting" "${LOG_DIR}/watchdog.log" | tail -n 50)
    if [ $RESTART_COUNT -gt 3 ]; then
        log_message "WARNING: Bot restarted ${RESTART_COUNT} times recently. Check for stability issues."
    fi
fi

log_message "Health check completed successfully"
EOF
chmod +x "${SCRIPT_DIR}/health_check.sh"

# Create a backup script
cat > "${SCRIPT_DIR}/backup_data.sh" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
BACKUP_DIR="${SCRIPT_DIR}/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/binancebot_backup_${TIMESTAMP}.tar.gz"
RETENTION_DAYS=14

# Ensure backup directory exists
mkdir -p "${BACKUP_DIR}"

echo "Creating backup of Binance Trading Bot data at $(date)..."

# Create a list of what to backup
BACKUP_TARGETS=(
    "${SCRIPT_DIR}/logs"
    "${SCRIPT_DIR}/state"
)

# Add any database or state files that might exist
[ -d "${SCRIPT_DIR}/data" ] && BACKUP_TARGETS+=("${SCRIPT_DIR}/data")
[ -d "${SCRIPT_DIR}/reports" ] && BACKUP_TARGETS+=("${SCRIPT_DIR}/reports")

# Create the backup
tar -czf "${BACKUP_FILE}" -C "${SCRIPT_DIR}" ${BACKUP_TARGETS[@]#$SCRIPT_DIR/}

# Check if backup was successful
if [ $? -eq 0 ]; then
    echo "Backup created successfully at: ${BACKUP_FILE}"
    echo "Backup size: $(du -h "${BACKUP_FILE}" | cut -f1)"
else
    echo "ERROR: Backup creation failed"
    exit 1
fi

# Remove backups older than retention period
echo "Cleaning up backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -name "binancebot_backup_*.tar.gz" -type f -mtime +${RETENTION_DAYS} -delete

# List remaining backups
echo "Available backups:"
ls -lh "${BACKUP_DIR}" | grep "binancebot_backup_"

echo "Backup process completed at $(date)"
EOF
chmod +x "${SCRIPT_DIR}/backup_data.sh"

# Create a temporary file for crontab
TEMP_CRON=$(mktemp)

# Export existing crontab
crontab -l > "$TEMP_CRON" 2>/dev/null || echo "# Binance Trading Bot crontab" > "$TEMP_CRON"

# Check if entries already exist
if grep -q "binancebot" "$TEMP_CRON"; then
    echo -e "${YELLOW}Cron jobs for Binance Trading Bot already exist. Updating...${NC}"
    # Remove existing entries
    sed -i '/binancebot/d' "$TEMP_CRON"
fi

# Add entries for comprehensive 24/7 operation
cat << EOF >> "$TEMP_CRON"
# Binance Trading Bot - 24/7 VPS Operation Setup

# Start after reboot (wait 60 seconds for network)
@reboot sleep 60 && cd ${SCRIPT_DIR} && ${SCRIPT_DIR}/run_bot.sh >> ${SCRIPT_DIR}/logs/cron_startup.log 2>&1

# Health check every 15 minutes
*/15 * * * * cd ${SCRIPT_DIR} && ${SCRIPT_DIR}/health_check.sh >> ${SCRIPT_DIR}/logs/health_check.log 2>&1

# Log rotation every hour
0 * * * * cd ${SCRIPT_DIR} && ${SCRIPT_DIR}/rotate_logs.sh >> ${SCRIPT_DIR}/logs/log_rotation.log 2>&1

# Daily backup at 00:00
0 0 * * * cd ${SCRIPT_DIR} && ${SCRIPT_DIR}/backup_data.sh >> ${SCRIPT_DIR}/logs/backup.log 2>&1

# Weekly full system resource report
0 0 * * 0 cd ${SCRIPT_DIR} && ${SCRIPT_DIR}/check_bot_status.sh > ${SCRIPT_DIR}/logs/weekly_status_report.log 2>&1
EOF

# Install new crontab
crontab "$TEMP_CRON"
rm "$TEMP_CRON"

echo -e "${GREEN}Cron jobs installed successfully!${NC}"
echo -e "${GREEN}The bot will now automatically:${NC}"
echo -e "${GREEN}- Start after system reboots${NC}"
echo -e "${GREEN}- Check its health every 15 minutes${NC}"
echo -e "${GREEN}- Rotate logs every hour to prevent disk space issues${NC}"
echo -e "${GREEN}- Perform daily backups at midnight${NC}"
echo -e "${GREEN}- Generate weekly system reports${NC}"
echo -e "\n${YELLOW}These cron jobs will ensure your bot runs 24/7 on your VPS with proper monitoring and maintenance.${NC}"