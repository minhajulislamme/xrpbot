#!/bin/bash

# Run the Binance Trading Bot with auto-restart capabilities
# Uses global Python packages (no virtual environment)

# Exit on error in pipeline
set -eo pipefail

# Get the absolute path of the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Define colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if the bot is already running
if pgrep -f "python3 ${SCRIPT_DIR}/main.py" > /dev/null; then
    echo -e "${YELLOW}Trading bot is already running. Use check_bot_status.sh to see its status.${NC}"
    exit 0
fi

# Create logs directory if it doesn't exist
mkdir -p "${SCRIPT_DIR}/logs"

# Create a watchdog script that will monitor and restart the bot if it crashes
cat > "${SCRIPT_DIR}/watchdog.sh" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
MAX_RESTARTS=5
RESTART_COUNT=0
RESTART_INTERVAL=60  # Seconds between restarts
COOLDOWN_PERIOD=3600  # 1 hour cooldown if too many restarts happen

echo "Starting bot watchdog at $(date)" >> "${SCRIPT_DIR}/logs/watchdog.log"

while true; do
    if [ $RESTART_COUNT -ge $MAX_RESTARTS ]; then
        echo "Too many restarts (${RESTART_COUNT}) in a short period. Entering cooldown for 1 hour at $(date)" >> "${SCRIPT_DIR}/logs/watchdog.log"
        sleep $COOLDOWN_PERIOD
        RESTART_COUNT=0
    fi

    # Check if bot process is running
    if ! pgrep -f "python3 ${SCRIPT_DIR}/main.py" > /dev/null; then
        echo "Bot process not found at $(date). Restarting..." >> "${SCRIPT_DIR}/logs/watchdog.log"
        python3 "${SCRIPT_DIR}/main.py" > "${SCRIPT_DIR}/logs/bot_console.log" 2>&1 &
        BOT_NEW_PID=$!
        echo $BOT_NEW_PID > "${SCRIPT_DIR}/bot.pid"
        echo "Bot restarted with PID $BOT_NEW_PID at $(date)" >> "${SCRIPT_DIR}/logs/watchdog.log"
        RESTART_COUNT=$((RESTART_COUNT + 1))
    fi
    
    sleep $RESTART_INTERVAL
done
EOF

chmod +x "${SCRIPT_DIR}/watchdog.sh"

# Start the bot with nohup to keep it running after SSH session closes
echo -e "${GREEN}Starting trading bot...${NC}"
echo -e "${YELLOW}Bot will run in the background with watchdog monitoring.${NC}"

# Make sure any existing watchdog process is stopped
if [ -f "${SCRIPT_DIR}/watchdog.pid" ]; then
    OLD_WATCHDOG_PID=$(cat "${SCRIPT_DIR}/watchdog.pid")
    if ps -p $OLD_WATCHDOG_PID > /dev/null; then
        echo -e "${YELLOW}Found existing watchdog process. Stopping it first...${NC}"
        kill $OLD_WATCHDOG_PID 2>/dev/null || true
    fi
    rm "${SCRIPT_DIR}/watchdog.pid"
fi

# Start the main bot process
nohup python3 "${SCRIPT_DIR}/main.py" > "${SCRIPT_DIR}/logs/bot_console.log" 2>&1 &
BOT_PID=$!
echo $BOT_PID > "${SCRIPT_DIR}/bot.pid"

# Wait a moment to ensure the bot starts properly
sleep 2

# Verify the bot is running
if ! ps -p $BOT_PID > /dev/null; then
    echo -e "${RED}Bot failed to start properly. Check logs for errors.${NC}"
    exit 1
fi

# Start the watchdog in the background
echo -e "${GREEN}Starting watchdog service...${NC}"
nohup "${SCRIPT_DIR}/watchdog.sh" > "${SCRIPT_DIR}/logs/watchdog_console.log" 2>&1 &
WATCHDOG_PID=$!
echo $WATCHDOG_PID > "${SCRIPT_DIR}/watchdog.pid"

# Verify the watchdog is running
if ! ps -p $WATCHDOG_PID > /dev/null; then
    echo -e "${RED}Watchdog failed to start properly. The bot is running but without watchdog protection.${NC}"
    exit 1
fi

echo -e "${GREEN}Bot started with PID ${BOT_PID}${NC}"
echo -e "${GREEN}Watchdog started with PID ${WATCHDOG_PID}${NC}"
echo -e "${GREEN}Use check_bot_status.sh to see the bot's status${NC}"
echo -e "${GREEN}Use stop_bot_manual.sh to stop the bot${NC}"

# Log the launch in syslog for better tracking
logger -t binancebot "Bot started with PID ${BOT_PID}, Watchdog PID ${WATCHDOG_PID}"