#!/bin/bash

# Script to set up Binance Bot environment on a VPS with VPN support
# and additional monitoring scripts for 24/7 operation without systemd

# Exit on any error
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "$SCRIPT_DIR"

echo "===== Binance Bot VPS Setup (24/7 Mode) ====="
echo "Setting up Binance Bot environment with VPN support and 24/7 monitoring tools..."

# Check and install required dependencies
install_dependencies() {
    echo "Installing required dependencies..."
    if [ -f /etc/debian_version ]; then
        sudo apt-get update
        sudo apt-get install -y whois screen cron logrotate procps curl jq
    elif [ -f /etc/redhat-release ]; then
        sudo yum install -y whois screen cronie logrotate procps curl jq
    fi
}

install_dependencies

# Run the main setup script if not already set up
if [ ! -d "venv" ]; then
    echo "Running main setup script..."
    bash setup.sh
else
    echo "Environment already set up. Skipping main setup."
fi

# Set up log rotation to prevent logs from growing too large
setup_log_rotation() {
    echo "Setting up log rotation..."
    sudo tee /etc/logrotate.d/binance_bot > /dev/null << 'EOF'
/home/minhajulislam/binancebot/logs/trading_bot_*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 minhajulislam minhajulislam
    sharedscripts
    postrotate
        touch /home/minhajulislam/binancebot/logs/rotated_at_$(date +\%Y\%m\%d_\%H\%M\%S)
    endscript
}
EOF
    echo "Log rotation configured."
}

setup_log_rotation

# Create monitoring and management scripts
echo "Creating 24/7 monitoring and management scripts..."

# Create VPN monitoring script
cat > check_vpn.sh << 'EOF'
#!/bin/bash
# Script to check VPN connection status

echo "===== VPN STATUS CHECK ====="
echo "$(date)"
echo "=========================="

# Check for VPN interfaces
if ip a | grep -q "tun\|tap\|wg\|nordlynx\|mullvad"; then
    echo "✅ VPN connection detected"
    echo "   Interface: $(ip a | grep -E "tun|tap|wg|nordlynx|mullvad" | head -1 | awk '{print $2}' | sed 's/://')"
    
    # Get public IP
    PUBLIC_IP=$(curl -s https://api.ipify.org)
    echo "   Public IP: $PUBLIC_IP"
    
    # Get IP location
    if command -v whois &> /dev/null; then
        LOCATION=$(whois "$PUBLIC_IP" | grep -i -E "country|city" | head -2)
        echo "   Location info: "
        echo "$LOCATION" | sed 's/^/     /'
    fi
    exit 0
else
    echo "❌ No VPN connection detected"
    echo "   Public IP: $(curl -s https://api.ipify.org)"
    echo ""
    echo "⚠️ Warning: Trading without VPN may expose your real IP address."
    exit 1
fi
EOF

# Create status check script
cat > check_status.sh << 'EOF'
#!/bin/bash
# Script to check the Binance bot status

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "$SCRIPT_DIR"

echo "===== BOT STATUS CHECK ====="
echo "$(date)"
echo "========================="

# Check if bot process is running in screen session
if screen -list | grep -q "binance_bot"; then
    echo "✅ Bot is running in screen session"
    SCREEN_INFO=$(screen -list | grep "binance_bot")
    echo "   Session: $SCREEN_INFO"
    
    # Check if the actual Python process is running
    if pgrep -f "python3 main.py" > /dev/null; then
        PID=$(pgrep -f "python3 main.py")
        echo "   Process ID: $PID"
        echo "   Running since: $(ps -o lstart= -p $PID)"
        echo "   CPU usage: $(ps -p $PID -o %cpu=)%"
        echo "   Memory usage: $(ps -p $PID -o %mem=)%"
        echo "   Uptime: $(ps -o etime= -p $PID)"
    else
        echo "⚠️ Screen session exists but Python process not found"
        echo "   You may need to restart the bot"
    fi
else
    echo "❌ Bot is NOT running in any screen session"
    
    # Still check if Python process is somehow running outside screen
    if pgrep -f "python3 main.py" > /dev/null; then
        PID=$(pgrep -f "python3 main.py")
        echo "⚠️ Bot process found outside screen session"
        echo "   Process ID: $PID"
        echo "   Running since: $(ps -o lstart= -p $PID)"
    fi
fi

# Check Binance API connection
echo ""
echo "=== Binance API Connection ==="
curl -s --max-time 5 https://api.binance.com/api/v3/ping > /dev/null
if [ $? -eq 0 ]; then
    echo "✅ Connection to Binance API is working"
    
    # Get server time difference
    SERVER_TIME=$(curl -s https://api.binance.com/api/v3/time | grep -o '"serverTime":[0-9]*' | cut -d':' -f2)
    LOCAL_TIME=$(date +%s)000
    TIME_DIFF=$((($SERVER_TIME - $LOCAL_TIME) / 1000))
    echo "   Time difference with Binance server: ${TIME_DIFF}s"
else
    echo "❌ Cannot connect to Binance API"
fi

# Check trading state if available
if [ -f "state/trading_state.json" ]; then
    echo ""
    echo "=== Trading State ==="
    echo "   Balance: $(grep -o '"current_balance":[^,]*' state/trading_state.json | cut -d':' -f2)"
    echo "   Total trades: $(grep -o '"total_trades":[^,]*' state/trading_state.json | cut -d':' -f2)"
    
    # Check if winning_trades exists in the file
    if grep -q '"winning_trades":' state/trading_state.json; then
        echo "   Winning trades: $(grep -o '"winning_trades":[^,]*' state/trading_state.json | cut -d':' -f2)"
    fi
    
    # Get last modified time of state file
    LAST_UPDATE=$(date -r state/trading_state.json '+%Y-%m-%d %H:%M:%S')
    echo "   Last state update: $LAST_UPDATE"
    
    # Check if state file is being actively updated
    TIME_DIFF=$(( $(date +%s) - $(date -r state/trading_state.json +%s) ))
    if [ $TIME_DIFF -gt 1800 ]; then  # More than 30 minutes
        echo "⚠️ Warning: State file hasn't been updated in $TIME_DIFF seconds"
    fi
fi

# Check log file health
TODAY=$(date +%Y%m%d)
LOGFILE="logs/trading_bot_${TODAY}.log"
if [ -f "$LOGFILE" ]; then
    echo ""
    echo "=== Log File Status ==="
    LAST_LOG_UPDATE=$(date -r "$LOGFILE" '+%Y-%m-%d %H:%M:%S')
    TIME_DIFF=$(( $(date +%s) - $(date -r "$LOGFILE" +%s) ))
    echo "   Log file: $LOGFILE"
    echo "   Size: $(du -h "$LOGFILE" | cut -f1)"
    echo "   Last updated: $LAST_LOG_UPDATE (${TIME_DIFF}s ago)"
    
    if [ $TIME_DIFF -gt 900 ]; then  # More than 15 minutes
        echo "⚠️ Warning: Log file hasn't been updated in $TIME_DIFF seconds"
    fi
fi

echo ""
echo "For detailed logs, run: ./check_logs.sh"
EOF

# Create log check script
cat > check_logs.sh << 'EOF'
#!/bin/bash
# Script to check and analyze Binance bot logs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "$SCRIPT_DIR"

TODAY=$(date +%Y%m%d)
LOGFILE="logs/trading_bot_${TODAY}.log"

echo "===== LOG CHECKER ====="
echo "$(date)"
echo "======================"

# Check if today's log exists
if [ ! -f "$LOGFILE" ]; then
    echo "❌ Today's log file not found: $LOGFILE"
    
    # List available log files
    echo ""
    echo "Available log files:"
    ls -lt logs/ 2>/dev/null | head -5 | awk '{print "   " $9 " (" $5 " bytes, " $6 " " $7 " " $8 ")"}'
    
    # Check if a specific log file was provided
    if [ ! -z "$1" ] && [ -f "$1" ]; then
        LOGFILE="$1"
        echo ""
        echo "Checking specified log file: $LOGFILE"
    else
        # Use most recent log file
        RECENT_LOG=$(ls -t logs/trading_bot_*.log 2>/dev/null | head -1)
        if [ ! -z "$RECENT_LOG" ]; then
            LOGFILE="$RECENT_LOG"
            echo ""
            echo "Using most recent log file: $LOGFILE"
        else
            echo "No log files found."
            exit 1
        fi
    fi
fi

# Display log statistics
echo ""
echo "=== Log Statistics ==="
LINES=$(wc -l < "$LOGFILE")
ERRORS=$(grep -c -i "error\|exception\|failed" "$LOGFILE")
WARNINGS=$(grep -c -i "warn\|warning" "$LOGFILE")
TRADES=$(grep -c -i "executed trade\|order filled" "$LOGFILE")

echo "   Total entries: $LINES"
echo "   Errors: $ERRORS"
echo "   Warnings: $WARNINGS"
echo "   Trades: $TRADES"
echo "   Log size: $(du -h "$LOGFILE" | cut -f1)"
echo "   Last updated: $(date -r "$LOGFILE" '+%Y-%m-%d %H:%M:%S')"

# Show recent errors if any
if [ $ERRORS -gt 0 ]; then
    echo ""
    echo "=== Recent Errors (last 5) ==="
    grep -i "error\|exception\|failed" "$LOGFILE" | tail -n 5 | sed 's/^/   /'
fi

# Show recent activity
echo ""
echo "=== Recent Log Entries (last 10) ==="
tail -n 10 "$LOGFILE" | sed 's/^/   /'

# Show trading activity
if [ $TRADES -gt 0 ]; then
    echo ""
    echo "=== Recent Trading Activity (last 3 trades) ==="
    grep -i "executed trade\|order filled" "$LOGFILE" | tail -n 3 | sed 's/^/   /'
fi

echo ""
echo "To view full log: less $LOGFILE"
echo "To watch live updates: tail -f $LOGFILE"
EOF

# Create a script to start the bot in a detached screen session (for 24/7 operation)
cat > start_bot_24_7.sh << 'EOF'
#!/bin/bash
# Script to start the Binance bot in a detached screen session for 24/7 operation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "$SCRIPT_DIR"

echo "===== STARTING BOT FOR 24/7 OPERATION ====="
echo "$(date)"
echo "=========================================="

# Activate virtual environment in screen session
SCREEN_CMD="cd $SCRIPT_DIR && source venv/bin/activate && python3 main.py"

# Check if a screen session is already running
if screen -list | grep -q "binance_bot"; then
    echo "⚠️ A screen session for the bot is already running!"
    echo "Do you want to terminate it and start a new one? (y/n)"
    read -r answer
    if [[ "$answer" == "y" ]]; then
        echo "Stopping existing screen session..."
        screen -S binance_bot -X quit
        sleep 2
    else
        echo "Startup cancelled. Bot is already running."
        exit 0
    fi
fi

# Check for VPN connection (optional)
echo "Checking for VPN connection..."
if ! ip a | grep -q "tun\|tap\|wg\|nordlynx\|mullvad"; then
    echo "⚠️ WARNING: No VPN connection detected!"
    echo "Do you want to continue without VPN? (y/n)"
    read -r answer
    if [[ "$answer" != "y" ]]; then
        echo "Bot startup cancelled. Please connect to a VPN first."
        exit 1
    fi
    echo "Continuing without VPN as requested..."
fi

# Create log directory if it doesn't exist
mkdir -p logs

# Create state directory if it doesn't exist  
mkdir -p state

# Start the bot in a screen session
echo "Starting Binance bot in a detached screen session..."
screen -dmS binance_bot bash -c "$SCREEN_CMD"

# Verify the screen session is running
sleep 2
if screen -list | grep -q "binance_bot"; then
    echo "✅ Bot successfully started in screen session"
    echo "To attach to the bot screen session: screen -r binance_bot"
    echo "To detach from screen after attaching: Press Ctrl+A then D"
    echo "To check bot status: ./check_status.sh"
else
    echo "❌ Failed to start bot in screen session"
    exit 1
fi

# Set up a cron job to monitor the bot and restart it if it crashes
echo "Setting up automatic monitoring..."
CRONTAB_FILE=$(mktemp)
crontab -l > "$CRONTAB_FILE" 2>/dev/null || echo "# Binance Bot monitoring" > "$CRONTAB_FILE"

# Check if the monitoring job already exists
if ! grep -q "monitor_bot.sh" "$CRONTAB_FILE"; then
    echo "*/10 * * * * $SCRIPT_DIR/monitor_bot.sh >> $SCRIPT_DIR/logs/monitor.log 2>&1" >> "$CRONTAB_FILE"
    crontab "$CRONTAB_FILE"
    echo "✅ Cron job set up to monitor bot every 10 minutes"
else
    echo "Monitoring cron job already exists"
fi

rm "$CRONTAB_FILE"

echo "Bot is now running in 24/7 mode with automatic monitoring."
echo "Use ./check_status.sh to check the bot status."
echo "Use ./check_logs.sh to view the bot logs."
EOF

# Create a script to stop the bot
cat > stop_bot.sh << 'EOF'
#!/bin/bash
# Script to stop the Binance bot running in a screen session

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "$SCRIPT_DIR"

echo "===== STOPPING BOT ====="
echo "$(date)"
echo "======================="

# Check if the bot is running in a screen session
if screen -list | grep -q "binance_bot"; then
    echo "Found bot screen session, stopping..."
    
    # Send SIGINT to the screen session (simulates pressing Ctrl+C)
    screen -S binance_bot -X stuff $'\003'
    
    # Wait for the process to clean up
    sleep 5
    
    # Check if the screen session is still running
    if screen -list | grep -q "binance_bot"; then
        echo "Bot didn't quit gracefully, terminating screen session..."
        screen -S binance_bot -X quit
    fi
    
    echo "✅ Bot stopped successfully"
else
    echo "No bot screen session found"
    
    # Check if any Python main.py processes are still running
    if pgrep -f "python3 main.py" > /dev/null; then
        echo "Found Python process running outside screen, killing..."
        pkill -f "python3 main.py"
        echo "Process terminated"
    else
        echo "No bot processes found"
    fi
fi

echo ""
echo "To check if the bot was stopped correctly: ./check_status.sh"
EOF

# Create a monitoring script to be run by cron
cat > monitor_bot.sh << 'EOF'
#!/bin/bash
# Script to monitor the bot and restart it if it's not running
# Will be executed by cron every 10 minutes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "$SCRIPT_DIR"

echo "===== BOT MONITORING CHECK ====="
echo "$(date)"
echo "=============================="

# Check if we have a screen session but no actual bot process
if screen -list | grep -q "binance_bot" && ! pgrep -f "python3 main.py" > /dev/null; then
    echo "Screen session exists but bot process is not running"
    echo "Terminating zombie screen session..."
    screen -S binance_bot -X quit
    sleep 2
    
    echo "Restarting bot..."
    bash "$SCRIPT_DIR/start_bot_24_7.sh"
    echo "Bot restarted at $(date)"
    exit 0
fi

# Check if neither screen session nor bot process exists
if ! screen -list | grep -q "binance_bot" && ! pgrep -f "python3 main.py" > /dev/null; then
    echo "Bot is not running, restarting..."
    bash "$SCRIPT_DIR/start_bot_24_7.sh"
    echo "Bot restarted at $(date)"
    exit 0
fi

# Check if the trading state file is being updated
if [ -f "$SCRIPT_DIR/state/trading_state.json" ]; then
    STATE_UPDATE_TIME=$(date -r "$SCRIPT_DIR/state/trading_state.json" +%s)
    CURRENT_TIME=$(date +%s)
    TIME_DIFF=$((CURRENT_TIME - STATE_UPDATE_TIME))
    
    # If the state file hasn't been updated in more than 30 minutes
    if [ $TIME_DIFF -gt 1800 ]; then
        echo "Trading state file hasn't been updated for $TIME_DIFF seconds"
        echo "Bot may be frozen, restarting..."
        
        # Stop the bot
        bash "$SCRIPT_DIR/stop_bot.sh"
        sleep 5
        
        # Start the bot again
        bash "$SCRIPT_DIR/start_bot_24_7.sh"
        echo "Bot restarted at $(date)"
        exit 0
    fi
fi

# Check VPN connection and alert if it's down (but don't restart bot)
if ! ip a | grep -q "tun\|tap\|wg\|nordlynx\|mullvad"; then
    echo "⚠️ WARNING: No VPN connection detected at $(date)"
    echo "Bot is running without VPN protection"
fi

echo "✅ Bot is running normally at $(date)"
EOF

# Make all scripts executable
chmod +x check_vpn.sh check_status.sh check_logs.sh start_bot_24_7.sh stop_bot.sh monitor_bot.sh

echo ""
echo "===== VPS SETUP FOR 24/7 OPERATION COMPLETE ====="
echo "The following scripts have been created to manage your Binance bot in 24/7 mode:"
echo ""
echo "  • ./start_bot_24_7.sh  - Start the bot for continuous 24/7 operation"
echo "  • ./stop_bot.sh        - Stop the running bot"
echo "  • ./check_status.sh    - Check bot status and Binance connection"
echo "  • ./check_logs.sh      - View and analyze bot logs"
echo "  • ./check_vpn.sh       - Check VPN connection status"
echo "  • ./monitor_bot.sh     - Automatically monitor and restart the bot (used by cron)"
echo ""
echo "To start the bot in 24/7 mode:"
echo "  1. Connect to your VPN if desired"
echo "  2. Run ./start_bot_24_7.sh"
echo ""
echo "Your bot will now:"
echo "  • Run in a screen session that persists even when you log out"
echo "  • Be monitored every 10 minutes via cron"
echo "  • Automatically restart if it crashes or freezes"
echo "  • Have its logs automatically rotated to prevent disk space issues"
echo ""
echo "To view the bot's live output:"
echo "  1. Run: screen -r binance_bot"
echo "  2. To detach without stopping the bot: Press Ctrl+A then D"
echo ""
echo "Happy trading!"