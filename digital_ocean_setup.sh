#!/bin/bash

# Digital Ocean VPS Setup Script for 24/7 Trading Bot
# This script handles everything needed to set up your trading bot on Digital Ocean

# Define colors for terminal output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print styled messages
print_message() {
  echo -e "${2:-$GREEN}$1${NC}"
}

print_message "================================================" "$BLUE"
print_message "    DIGITAL OCEAN TRADING BOT SETUP SCRIPT" "$BLUE"
print_message "================================================" "$BLUE"
print_message "This script will set up your trading bot to run 24/7 on Digital Ocean."

# Step 1: Update system and install prerequisites
print_message "\n[Step 1/5] Updating system and installing prerequisites..." "$YELLOW"
sudo apt update
sudo apt upgrade -y
sudo apt install -y build-essential python3-dev python3-pip wget curl git supervisor htop

# Step 2: Configure swap space if needed (improves stability)
print_message "\n[Step 2/5] Setting up swap space for stability..." "$YELLOW"
if [[ $(free -m | awk '/^Swap:/ {print $2}') -eq 0 ]]; then
  print_message "No swap detected, creating 2GB swap file..." "$YELLOW"
  sudo fallocate -l 2G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  print_message "Swap file created and enabled" "$GREEN"
else
  print_message "Swap already configured" "$GREEN"
fi

# Step 3: Install TA-Lib (optimized for Digital Ocean)
print_message "\n[Step 3/5] Installing TA-Lib (optimized for Digital Ocean)..." "$YELLOW"

# Create a temporary directory for installation
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Download and build TA-Lib from source
wget http://prdownloads.sourceforge.net/ta-lib/ta-lib-0.4.0-src.tar.gz
tar -xzf ta-lib-0.4.0-src.tar.gz
cd ta-lib/
./configure --prefix=/usr
make
sudo make install

# Create symlinks to ensure the library is found
if [ -f "/usr/lib/libta_lib.so.0" ]; then
  sudo ln -sf /usr/lib/libta_lib.so.0 /usr/lib/libta-lib.so
fi
if [ -f "/usr/lib/libta_lib.so" ]; then
  sudo ln -sf /usr/lib/libta_lib.so /usr/lib/libta-lib.so
fi
if [ -f "/usr/lib/libta_lib.a" ]; then
  sudo ln -sf /usr/lib/libta_lib.a /usr/lib/libta-lib.a
fi

# Update the dynamic linker cache
sudo ldconfig

# Install NumPy first (dependency for TA-Lib)
pip install numpy

# Install TA-Lib Python wrapper with environment variables
export TA_LIBRARY_PATH=/usr/lib
export TA_INCLUDE_PATH=/usr/include
LIBRARY_PATH=/usr/lib LD_LIBRARY_PATH=/usr/lib C_INCLUDE_PATH=/usr/include pip install --no-cache-dir ta-lib

# Verify TA-Lib installation
if python3 -c "import talib" &>/dev/null; then
  print_message "TA-Lib installed successfully!" "$GREEN"
else
  print_message "TA-Lib installation failed. Trying alternative installation method..." "$YELLOW"
  
  # Try installing with specific build flags
  pip install --no-cache-dir --no-build-isolation --global-option=build_ext --global-option="-L/usr/lib/" --global-option="-I/usr/include/" ta-lib
  
  # Check again
  if python3 -c "import talib" &>/dev/null; then
    print_message "TA-Lib installed successfully with alternative method!" "$GREEN"
  else
    print_message "❌ TA-Lib installation failed. Please check the error messages and try again." "$RED"
    print_message "You may need to manually install TA-Lib following the documentation." "$RED"
    exit 1
  fi
fi

# Clean up temporary files
cd ~
rm -rf "$TEMP_DIR"

# Step 4: Install Python dependencies
print_message "\n[Step 4/5] Installing Python dependencies..." "$YELLOW"

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Install requirements
if [ -f "$SCRIPT_DIR/requirements.txt" ]; then
  pip install -r "$SCRIPT_DIR/requirements.txt"
else
  print_message "Requirements file not found. Installing common trading bot packages..." "$YELLOW"
  pip install python-binance pandas numpy matplotlib websocket-client schedule python-dotenv ccxt requests tqdm
fi

# Step 5: Configure supervisor for 24/7 operation
print_message "\n[Step 5/5] Setting up 24/7 operation with supervisor..." "$YELLOW"

# Create supervisor configuration
SUPERVISOR_CONF="/etc/supervisor/conf.d/tradingbot.conf"
sudo tee "$SUPERVISOR_CONF" > /dev/null << EOF
[program:tradingbot]
directory=$SCRIPT_DIR
command=python3 $SCRIPT_DIR/main.py
user=$(whoami)
autostart=true
autorestart=true
startsecs=10
startretries=3
stopwaitsecs=300
stdout_logfile=$SCRIPT_DIR/logs/supervisor_stdout.log
stderr_logfile=$SCRIPT_DIR/logs/supervisor_stderr.log
EOF

# Create logs directory
mkdir -p "$SCRIPT_DIR/logs"

# Create convenience scripts
cat > "$SCRIPT_DIR/start_bot.sh" << EOF
#!/bin/bash
echo "Starting trading bot..."
sudo supervisorctl start tradingbot
sudo supervisorctl status tradingbot
EOF
chmod +x "$SCRIPT_DIR/start_bot.sh"

cat > "$SCRIPT_DIR/stop_bot.sh" << EOF
#!/bin/bash
echo "Stopping trading bot..."
sudo supervisorctl stop tradingbot
sudo supervisorctl status tradingbot
EOF
chmod +x "$SCRIPT_DIR/stop_bot.sh"

cat > "$SCRIPT_DIR/check_bot.sh" << EOF
#!/bin/bash
echo "Checking trading bot status..."
sudo supervisorctl status tradingbot
echo ""
echo "Last 20 log lines:"
tail -n 20 $SCRIPT_DIR/logs/supervisor_stdout.log
EOF
chmod +x "$SCRIPT_DIR/check_bot.sh"

# Reload supervisor configuration
sudo supervisorctl update
sudo supervisorctl reread

print_message "\n================================================" "$BLUE"
print_message "    SETUP COMPLETE! YOUR BOT IS READY TO RUN" "$BLUE"
print_message "================================================" "$BLUE"
print_message "\nUseful Commands:" "$YELLOW"
print_message "✅ Start the bot:   $SCRIPT_DIR/start_bot.sh" "$GREEN"
print_message "🛑 Stop the bot:    $SCRIPT_DIR/stop_bot.sh" "$GREEN"
print_message "🔍 Check status:    $SCRIPT_DIR/check_bot.sh" "$GREEN"

print_message "\nImportant Notes:" "$YELLOW"
print_message "1. Make sure you've configured your API keys in the config file" "$GREEN"
print_message "2. The bot will automatically restart if it crashes" "$GREEN"
print_message "3. Check logs in $SCRIPT_DIR/logs/ if you encounter issues" "$GREEN"

# Start the bot automatically
print_message "\nStarting your trading bot..." "$YELLOW"
sudo supervisorctl start tradingbot
sudo supervisorctl status tradingbot

print_message "\nYour trading bot is now running 24/7! 🚀" "$BLUE"