#!/bin/bash

# Stop the Binance Trading Bot and its watchdog
# This script ensures a clean shutdown of all bot-related processes

# Get the absolute path of the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Define colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to stop a process with graceful shutdown and force kill if needed
stop_process() {
    local pid=$1
    local name=$2
    local pid_file=$3
    
    if [ -z "$pid" ]; then
        echo -e "${YELLOW}No ${name} process found.${NC}"
        [ -f "$pid_file" ] && rm -f "$pid_file"
        return
    fi
    
    echo -e "${YELLOW}Sending SIGTERM to ${name} process (PID: ${pid})...${NC}"
    kill -TERM $pid 2>/dev/null
    
    # Wait up to 30 seconds for the process to exit gracefully
    for i in {1..30}; do
        if ! ps -p $pid > /dev/null; then
            echo -e "${GREEN}${name} has stopped gracefully.${NC}"
            [ -f "$pid_file" ] && rm -f "$pid_file"
            return
        fi
        echo -n "."
        sleep 1
    done
    
    # If the process is still running, force kill it
    echo -e "\n${RED}${name} didn't stop gracefully. Forcing termination...${NC}"
    kill -9 $pid 2>/dev/null
    
    # Check if the kill was successful
    if ! ps -p $pid > /dev/null; then
        echo -e "${GREEN}${name} has been terminated.${NC}"
        [ -f "$pid_file" ] && rm -f "$pid_file"
    else
        echo -e "${RED}Failed to terminate ${name}. Please check process manually.${NC}"
    fi
}

echo -e "${GREEN}Stopping Binance Trading Bot...${NC}"

# First stop the bot process
if [ -f "${SCRIPT_DIR}/bot.pid" ]; then
    BOT_PID=$(cat "${SCRIPT_DIR}/bot.pid")
    echo -e "${GREEN}Found bot PID file: ${BOT_PID}${NC}"
else
    echo -e "${YELLOW}Bot PID file not found. Searching for bot process...${NC}"
    BOT_PID=$(pgrep -f "python3 ${SCRIPT_DIR}/main.py")
    if [ -n "$BOT_PID" ]; then
        echo -e "${GREEN}Found bot process with PID ${BOT_PID}${NC}"
    fi
fi

# Stop the bot process
stop_process "$BOT_PID" "Bot" "${SCRIPT_DIR}/bot.pid"

# Then stop the watchdog
if [ -f "${SCRIPT_DIR}/watchdog.pid" ]; then
    WATCHDOG_PID=$(cat "${SCRIPT_DIR}/watchdog.pid")
    echo -e "${GREEN}Found watchdog PID file: ${WATCHDOG_PID}${NC}"
else
    echo -e "${YELLOW}Watchdog PID file not found. Searching for watchdog process...${NC}"
    WATCHDOG_PID=$(pgrep -f "${SCRIPT_DIR}/watchdog.sh")
    if [ -n "$WATCHDOG_PID" ]; then
        echo -e "${GREEN}Found watchdog process with PID ${WATCHDOG_PID}${NC}"
    fi
fi

# Stop the watchdog process
stop_process "$WATCHDOG_PID" "Watchdog" "${SCRIPT_DIR}/watchdog.pid"

# Double-check for any remaining processes
BOT_PROCESSES=$(pgrep -f "python3 ${SCRIPT_DIR}/main.py")
WATCHDOG_PROCESSES=$(pgrep -f "${SCRIPT_DIR}/watchdog.sh")

if [ -n "$BOT_PROCESSES" ] || [ -n "$WATCHDOG_PROCESSES" ]; then
    echo -e "${RED}Some processes may still be running:${NC}"
    [ -n "$BOT_PROCESSES" ] && echo -e "${RED}Bot processes: $BOT_PROCESSES${NC}"
    [ -n "$WATCHDOG_PROCESSES" ] && echo -e "${RED}Watchdog processes: $WATCHDOG_PROCESSES${NC}"
    echo -e "${YELLOW}Consider investigating or using 'kill -9' manually.${NC}"
else
    echo -e "${GREEN}All Binance Trading Bot processes have been successfully stopped.${NC}"
fi

# Log the shutdown
logger -t binancebot "Bot and watchdog processes stopped manually"