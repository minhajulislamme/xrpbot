#!/bin/bash

# Binance Trading Bot Setup Script for 24/7 VPS Operation
# This script sets up the trading bot with global Python packages (no virtual environment)

set -e  # Exit immediately if a command exits with non-zero status

# Define colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get the absolute path of the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
BOT_DIR=$SCRIPT_DIR
SERVICE_NAME="tradingbot"

# Function to display messages with color
print_message() {
    echo -e "${2:-$GREEN}$1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if script is run as root
if [ "$EUID" -eq 0 ]; then
    print_message "⚠️  This script should not be run as root directly." "$YELLOW"
    print_message "Please run it as a regular user with sudo privileges." "$YELLOW"
    exit 1
fi

# Check for sudo access
if ! command_exists sudo; then
    print_message "❌ sudo is not installed. Please install sudo and try again." "$RED"
    exit 1
fi

if ! sudo -n true 2>/dev/null; then
    print_message "⚠️  This script requires sudo privileges to install system packages." "$YELLOW"
    print_message "You may be prompted for your password." "$YELLOW"
fi

# Check if Python 3 is installed
if ! command_exists python3; then
    print_message "❌ Python 3 is not installed. Please install Python 3.8+ and try again." "$RED"
    exit 1
fi

# Check Python version
PY_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PY_MAJOR=$(echo "$PY_VERSION" | cut -d. -f1)
PY_MINOR=$(echo "$PY_VERSION" | cut -d. -f2)

if [ "$PY_MAJOR" -lt 3 ] || ([ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 8 ]); then
    print_message "❌ Python 3.8+ is required. Your version: $PY_VERSION" "$RED"
    exit 1
else
    print_message "✅ Python version check passed: $PY_VERSION" "$GREEN"
fi

# Continue with the rest of the setup

# Check for pip
if ! command_exists pip3; then
    print_message "❌ pip3 is not installed. Installing it now..." "$YELLOW"
    sudo apt-get update
    sudo apt-get install -y python3-pip
fi

# Install required system packages if not already installed
print_message "📦 Checking and installing required system packages..."
sudo apt-get update
sudo apt-get install -y python3-dev python3-pip bc curl wget htop build-essential

# Create required directories
print_message "📁 Creating necessary directories..."
mkdir -p "${BOT_DIR}/logs"
mkdir -p "${BOT_DIR}/state"
mkdir -p "${BOT_DIR}/reports"
mkdir -p "${BOT_DIR}/backups"

# Ensure TA-Lib is properly installed with no-cache-dir option
print_message "📊 Installing TA-Lib specifically with no-cache-dir option..."
if python3 -c "import talib" &>/dev/null; then
    print_message "TA-Lib is already installed." "$YELLOW"
else
    print_message "TA-Lib not found. Installing TA-Lib C library first..." "$YELLOW"
    bash "${BOT_DIR}/install_talib.sh"
    
    print_message "Installing TA-Lib Python wrapper with no-cache-dir..." "$YELLOW"
    sudo pip3 install --no-cache-dir ta-lib
    
    # Verify installation
    if ! python3 -c "import talib" &>/dev/null; then
        print_message "❌ TA-Lib installation failed. Please check the error messages." "$RED"
        exit 1
    fi
fi

# Install Python dependencies globally
print_message "📚 Installing Python dependencies globally..."
sudo pip3 install --upgrade pip

# Create a temp requirements file without ta-lib
grep -v "ta-lib" "${BOT_DIR}/requirements.txt" > "${BOT_DIR}/temp_requirements.txt"

# Install other packages with no-cache-dir
print_message "Installing packages from requirements.txt with no-cache-dir..."
sudo pip3 install --no-cache-dir -r "${BOT_DIR}/temp_requirements.txt"

# Clean up
rm -f "${BOT_DIR}/temp_requirements.txt"

# Add extra packages for reliability and monitoring
print_message "🔍 Installing additional packages for monitoring and reliability..."
sudo pip3 install --no-cache-dir psutil requests schedule retrying loguru apscheduler

# Ensure all scripts are executable
print_message "🔧 Making scripts executable..."
find "${BOT_DIR}" -name "*.sh" -exec chmod +x {} \;

# Display VPS optimization recommendations
print_message "🖥️  VPS Optimization Recommendations:" "$CYAN"
print_message "1. Ensure your VPS has at least 1GB of RAM" "$YELLOW"
print_message "2. Configure swap space if RAM is limited:" "$YELLOW"
print_message "   sudo fallocate -l 2G /swapfile" "$YELLOW"
print_message "   sudo chmod 600 /swapfile" "$YELLOW"
print_message "   sudo mkswap /swapfile" "$YELLOW"
print_message "   sudo swapon /swapfile" "$YELLOW"
print_message "   echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab" "$YELLOW"
print_message "3. Consider setting up a firewall with ufw:" "$YELLOW"
print_message "   sudo apt install ufw" "$YELLOW"
print_message "   sudo ufw allow ssh" "$YELLOW"
print_message "   sudo ufw enable" "$YELLOW"

# Set up supervisor configuration
print_message "🔧 Setting up supervisor configuration..."
SUPERVISOR_CONF="/etc/supervisor/conf.d/${SERVICE_NAME}.conf"

sudo tee "$SUPERVISOR_CONF" > /dev/null << EOF
[program:${SERVICE_NAME}]
directory=${BOT_DIR}
command=python3 ${BOT_DIR}/main.py
user=$(whoami)
autostart=true
autorestart=true
startsecs=10
startretries=3
stopwaitsecs=300
stdout_logfile=${BOT_DIR}/logs/supervisor_stdout.log
stderr_logfile=${BOT_DIR}/logs/supervisor_stderr.log
EOF

# Create start and stop scripts
print_message "📝 Creating convenient start/stop scripts..."

# Create start script
cat > "${BOT_DIR}/start_bot.sh" << EOF
#!/bin/bash
echo "Starting Binance Trading Bot..."
sudo supervisorctl start ${SERVICE_NAME}
sudo supervisorctl status ${SERVICE_NAME}
EOF
chmod +x "${BOT_DIR}/start_bot.sh"

# Create stop script
cat > "${BOT_DIR}/stop_bot.sh" << EOF
#!/bin/bash
echo "Stopping Binance Trading Bot..."
sudo supervisorctl stop ${SERVICE_NAME}
sudo supervisorctl status ${SERVICE_NAME}
EOF
chmod +x "${BOT_DIR}/stop_bot.sh"

# Create status check script
cat > "${BOT_DIR}/check_status.sh" << EOF
#!/bin/bash
echo "Checking Binance Trading Bot status..."
sudo supervisorctl status ${SERVICE_NAME}
echo ""
echo "Last 20 log lines:"
tail -n 20 ${BOT_DIR}/logs/supervisor_stdout.log
EOF
chmod +x "${BOT_DIR}/check_status.sh"

# Create a backup script
cat > "${BOT_DIR}/backup_data.sh" << EOF
#!/bin/bash
BACKUP_DIR="\${HOME}/binancebot_backups"
TIMESTAMP=\$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="\${BACKUP_DIR}/binancebot_backup_\${TIMESTAMP}.tar.gz"

mkdir -p "\${BACKUP_DIR}"

echo "Creating backup of Binance Trading Bot data..."
tar -czf "\${BACKUP_FILE}" -C "${BOT_DIR}" state reports logs

echo "Backup created at: \${BACKUP_FILE}"
echo "Removing backups older than 7 days..."
find "\${BACKUP_DIR}" -name "binancebot_backup_*.tar.gz" -type f -mtime +7 -delete
EOF
chmod +x "${BOT_DIR}/backup_data.sh"

# Reload supervisor configuration
print_message "🔄 Reloading supervisor configuration..."
sudo supervisorctl update
sudo supervisorctl reread

print_message "✅ Setup completed successfully with global Python packages!"
print_message "📊 To start the bot: ${BOT_DIR}/start_bot.sh"
print_message "🛑 To stop the bot: ${BOT_DIR}/stop_bot.sh"
print_message "ℹ️  To check status: ${BOT_DIR}/check_status.sh"
print_message "💾 To backup data: ${BOT_DIR}/backup_data.sh"

# Display status
echo ""
print_message "Current bot status:"
sudo supervisorctl status ${SERVICE_NAME}