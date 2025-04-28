#!/bin/bash

# Check the status of the Binance Trading Bot with enhanced monitoring
# This script provides detailed information about the bot's status and system resources
# Uses global Python packages (no virtual environment)

# Get the absolute path of the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Define colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

echo -e "${CYAN}=== Binance Trading Bot Status Check ===${NC}"
echo -e "${CYAN}Time: $(date)${NC}"

# Display system uptime
echo -e "${CYAN}=== System Information ===${NC}"
echo -e "${YELLOW}System uptime: $(uptime)${NC}"

# Display system load
if command_exists "free"; then
    echo -e "${YELLOW}Memory usage:${NC}"
    free -h
fi

if command_exists "df"; then
    echo -e "${YELLOW}Disk usage:${NC}"
    df -h | grep -E "(Filesystem|/$)"
fi

# Check if the watchdog is running
echo -e "\n${CYAN}=== Watchdog Status ===${NC}"
if [ -f "${SCRIPT_DIR}/watchdog.pid" ]; then
    WATCHDOG_PID=$(cat "${SCRIPT_DIR}/watchdog.pid")
    if ps -p $WATCHDOG_PID > /dev/null; then
        echo -e "${GREEN}Watchdog is running with PID ${WATCHDOG_PID}${NC}"
        echo -e "${YELLOW}Watchdog runtime: $(ps -o etime= -p $WATCHDOG_PID)${NC}"
    else
        echo -e "${RED}Watchdog PID file exists but process ${WATCHDOG_PID} is not running${NC}"
        echo -e "${YELLOW}Starting watchdog...${NC}"
        nohup "${SCRIPT_DIR}/watchdog.sh" > "${SCRIPT_DIR}/logs/watchdog_console.log" 2>&1 &
        WATCHDOG_PID=$!
        echo $WATCHDOG_PID > "${SCRIPT_DIR}/watchdog.pid"
        echo -e "${GREEN}Watchdog restarted with PID ${WATCHDOG_PID}${NC}"
    fi
else
    WATCHDOG_PID=$(pgrep -f "${SCRIPT_DIR}/watchdog.sh")
    if [ -n "$WATCHDOG_PID" ]; then
        echo -e "${GREEN}Watchdog is running with PID ${WATCHDOG_PID} (PID file missing)${NC}"
        echo $WATCHDOG_PID > "${SCRIPT_DIR}/watchdog.pid"
    else
        echo -e "${RED}Watchdog is not running${NC}"
        echo -e "${YELLOW}Starting watchdog...${NC}"
        nohup "${SCRIPT_DIR}/watchdog.sh" > "${SCRIPT_DIR}/logs/watchdog_console.log" 2>&1 &
        WATCHDOG_PID=$!
        echo $WATCHDOG_PID > "${SCRIPT_DIR}/watchdog.pid"
        echo -e "${GREEN}Watchdog started with PID ${WATCHDOG_PID}${NC}"
    fi
fi

# Check if the bot is running
echo -e "\n${CYAN}=== Bot Process Status ===${NC}"
if [ -f "${SCRIPT_DIR}/bot.pid" ]; then
    BOT_PID=$(cat "${SCRIPT_DIR}/bot.pid")
    if ps -p $BOT_PID > /dev/null; then
        echo -e "${GREEN}Bot is running with PID ${BOT_PID}${NC}"
        echo -e "${YELLOW}Runtime: $(ps -o etime= -p $BOT_PID)${NC}"
        
        # Show memory usage
        MEM_USAGE=$(ps -o rss= -p $BOT_PID)
        MEM_USAGE_MB=$(( $MEM_USAGE / 1024 ))
        echo -e "${YELLOW}Memory usage: ${MEM_USAGE_MB} MB${NC}"
        
        # Show CPU usage
        if command_exists "top"; then
            CPU_USAGE=$(top -b -n 1 -p $BOT_PID | grep -E "^[[:space:]]*$BOT_PID" | awk '{print $9}')
            echo -e "${YELLOW}CPU usage: ${CPU_USAGE}%${NC}"
        fi
    else
        echo -e "${RED}Found bot.pid file but process ${BOT_PID} is not running${NC}"
        echo -e "${YELLOW}The bot may have crashed or been terminated improperly${NC}"
        echo -e "${YELLOW}Watchdog should restart it automatically if enabled${NC}"
    fi
else
    # Try to find the bot process even without pid file
    BOT_PID=$(pgrep -f "python3 ${SCRIPT_DIR}/main.py")
    if [ -n "$BOT_PID" ]; then
        echo -e "${GREEN}Bot is running with PID ${BOT_PID} (PID file missing)${NC}"
        echo -e "${YELLOW}Runtime: $(ps -o etime= -p $BOT_PID)${NC}"
        
        # Save the found PID to the pid file
        echo $BOT_PID > "${SCRIPT_DIR}/bot.pid"
        echo -e "${GREEN}Created new bot.pid file${NC}"
    else
        echo -e "${RED}Bot is not running${NC}"
    fi
fi

# Display Python packages and version information
echo -e "\n${CYAN}=== Python Environment Information ===${NC}"
echo -e "${YELLOW}Python version:${NC}"
python3 --version

echo -e "${YELLOW}Key packages:${NC}"
packages=("python-binance" "numpy" "pandas" "ta" "ta-lib" "websocket-client" "ccxt")
for pkg in "${packages[@]}"; do
    version=$(python3 -c "import importlib.metadata; print(f'${pkg}: {importlib.metadata.version(\"${pkg}\")}')" 2>/dev/null || echo "${pkg}: Not installed")
    echo -e "${version}"
done

# Display the latest watchdog log entries
echo -e "\n${CYAN}=== Latest Watchdog Log Entries ===${NC}"
WATCHDOG_LOG="${SCRIPT_DIR}/logs/watchdog.log"
if [ -f "$WATCHDOG_LOG" ]; then
    echo -e "${YELLOW}Last modified: $(stat -c '%y' $WATCHDOG_LOG)${NC}"
    echo ""
    tail -n 10 "$WATCHDOG_LOG"
else
    echo -e "${RED}No watchdog log file found${NC}"
fi

# Display the latest log entries
echo -e "\n${CYAN}=== Latest Bot Log Entries ===${NC}"
LOG_FILE="${SCRIPT_DIR}/logs/bot_console.log"
if [ -f "$LOG_FILE" ]; then
    echo -e "${YELLOW}Last modified: $(stat -c '%y' $LOG_FILE)${NC}"
    echo -e "${YELLOW}Log file size: $(du -h $LOG_FILE | cut -f1)${NC}"
    echo ""
    tail -n 20 "$LOG_FILE"
else
    echo -e "${RED}No log file found at ${LOG_FILE}${NC}"
fi

# Display latest trading log if available
echo -e "\n${CYAN}=== Latest Trading Log Entries ===${NC}"
LATEST_LOG=$(find "${SCRIPT_DIR}/logs" -name "trading_bot_*.log" -type f -printf "%T@ %p\n" | sort -nr | head -n1 | cut -d' ' -f2-)
if [ -n "$LATEST_LOG" ]; then
    echo -e "${YELLOW}Log file: ${LATEST_LOG}${NC}"
    echo -e "${YELLOW}Last modified: $(stat -c '%y' "$LATEST_LOG")${NC}"
    echo -e "${YELLOW}Log file size: $(du -h "$LATEST_LOG" | cut -f1)${NC}"
    echo ""
    tail -n 20 "$LATEST_LOG"
else
    echo -e "${RED}No trading log files found${NC}"
fi

# Check for any recent errors
echo -e "\n${CYAN}=== Recent Errors ===${NC}"
if [ -f "$LOG_FILE" ]; then
    ERROR_COUNT=$(grep -i "error\|exception\|traceback" "$LOG_FILE" | wc -l)
    if [ $ERROR_COUNT -gt 0 ]; then
        echo -e "${RED}Found ${ERROR_COUNT} errors/exceptions in the log${NC}"
        echo -e "${YELLOW}Last 5 errors:${NC}"
        grep -i "error\|exception\|traceback" "$LOG_FILE" | tail -n 5
    else
        echo -e "${GREEN}No recent errors found in the logs${NC}"
    fi
fi

# Monitoring summary
echo -e "\n${CYAN}=== Monitoring Summary ===${NC}"
if ps -p ${BOT_PID:-0} > /dev/null && ps -p ${WATCHDOG_PID:-0} > /dev/null; then
    echo -e "${GREEN}✓ Bot is running properly with watchdog protection${NC}"
elif ps -p ${BOT_PID:-0} > /dev/null; then
    echo -e "${YELLOW}⚠ Bot is running but watchdog is not active${NC}"
elif ps -p ${WATCHDOG_PID:-0} > /dev/null; then
    echo -e "${YELLOW}⚠ Watchdog is running but bot process not detected${NC}"
    echo -e "${YELLOW}   Watchdog should restart the bot automatically${NC}"
else
    echo -e "${RED}✗ Both bot and watchdog are not running${NC}"
    echo -e "${RED}   Run ./run_bot.sh to start the bot${NC}"
fi