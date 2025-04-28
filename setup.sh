#!/bin/bash

# Script to set up a virtual environment and install all requirements for the Binance bot
# including TA-Lib which requires special handling

# Exit on any error
set -e

# Check for root privileges (for system installs)
if [ "$EUID" -eq 0 ]; then
    echo "Please do not run this script as root. Use a normal user with sudo privileges."
    exit 1
fi

# Check for Python3 and pip
if ! command -v python3 &> /dev/null; then
    echo "Python3 is not installed. Please install Python3 and rerun this script."
    exit 1
fi
if ! command -v pip3 &> /dev/null; then
    echo "pip3 is not installed. Installing pip3..."
    sudo apt-get update && sudo apt-get install -y python3-pip
fi

echo "Setting up Binance Bot environment with virtual environment..."

# Install TA-Lib dependencies and other build requirements
echo "Installing TA-Lib dependencies and build tools..."
if [ -f /etc/debian_version ]; then
    # Debian/Ubuntu
    sudo apt-get update
    sudo apt-get install -y build-essential wget pkg-config python3-venv python3-dev
    sudo apt-get install -y cmake libssl-dev libffi-dev
    sudo apt-get install -y libcurl4-openssl-dev  # Required for some Python packages
    sudo apt-get install -y python3-setuptools python3-pip  # Ensure pip and setuptools are up-to-date
    sudo apt-get install -y git  # Often needed for pip installations
    # Fix: Install autoconf and automake for patchelf/ta-lib build
    sudo apt-get install -y autoconf automake

    # Download and install TA-Lib
    if [ ! -d "ta-lib" ]; then
        wget http://prdownloads.sourceforge.net/ta-lib/ta-lib-0.4.0-src.tar.gz
        tar -xzf ta-lib-0.4.0-src.tar.gz
        cd ta-lib/
        ./configure --prefix=/usr
        make
        sudo make install
        cd ..
        rm -rf ta-lib-0.4.0-src.tar.gz
    else
        echo "TA-Lib source already downloaded, trying to build and install..."
        cd ta-lib/
        ./configure --prefix=/usr
        make
        sudo make install
        cd ..
    fi
    
    # Ensure library path is updated
    sudo ldconfig
elif [ -f /etc/redhat-release ]; then
    # CentOS/RHEL
    sudo yum groupinstall -y "Development Tools"
    sudo yum install -y wget python3-venv python3-devel
    sudo yum install -y cmake openssl-devel libffi-devel
    sudo yum install -y libcurl-devel
    sudo yum install -y python3-setuptools python3-pip
    sudo yum install -y git
    # Fix: Install autoconf and automake for patchelf/ta-lib build
    sudo yum install -y autoconf automake

    # Download and install TA-Lib
    if [ ! -d "ta-lib" ]; then
        wget http://prdownloads.sourceforge.net/ta-lib/ta-lib-0.4.0-src.tar.gz
        tar -xzf ta-lib-0.4.0-src.tar.gz
        cd ta-lib/
        ./configure --prefix=/usr
        make
        sudo make install
        cd ..
        rm -rf ta-lib-0.4.0-src.tar.gz
    else
        echo "TA-Lib source already downloaded, trying to build and install..."
        cd ta-lib/
        ./configure --prefix=/usr
        make
        sudo make install
        cd ..
    fi
    
    # Ensure library path is updated
    sudo ldconfig
else
    echo "Unsupported OS. Please install TA-Lib manually according to your OS instructions."
    echo "See: https://github.com/mrjbq7/ta-lib#dependencies"
    exit 1
fi

# Update LD_LIBRARY_PATH to find the TA-Lib library
export LD_LIBRARY_PATH=/usr/lib:$LD_LIBRARY_PATH

# Create and activate virtual environment
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
else
    echo "Virtual environment already exists. Skipping creation."
fi

# Activate virtual environment
source venv/bin/activate

# Install Python packages in the virtual environment
echo "Installing Python requirements in virtual environment..."
pip install --upgrade pip setuptools wheel

# Install TA-Lib Python wrapper specifically before other requirements
if ! python -c "import talib" &> /dev/null; then
    echo "Installing TA-Lib Python wrapper..."
    export TA_LIBRARY_PATH=/usr/lib
    export TA_INCLUDE_PATH=/usr/include
    pip install numpy
    pip install --no-binary :all: ta-lib
else
    echo "TA-Lib Python wrapper already installed."
fi

# Install other dependencies
echo "Installing remaining Python requirements..."
# Use system-provided cmake instead of letting pip build it
pip install --upgrade cmake

# Install remaining requirements
if [ -f requirements.txt ]; then
    pip install -r requirements.txt
else
    echo "requirements.txt not found. Skipping Python requirements install."
fi

# Make all .sh scripts executable
chmod +x *.sh

echo "\nSetup complete! To activate the environment: source venv/bin/activate"
echo "To start the bot: ./start_bot_24_7.sh"
echo "To check status: ./check_status.sh"