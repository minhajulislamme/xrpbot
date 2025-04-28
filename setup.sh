#!/bin/bash

# Script to set up a virtual environment and install all requirements for the Binance bot
# including TA-Lib which requires special handling

# Exit on any error
set -e

echo "Setting up Binance Bot environment with virtual environment..."

# Install TA-Lib dependencies (required for ta-lib Python package)
echo "Installing TA-Lib dependencies..."
if [ -f /etc/debian_version ]; then
    # Debian/Ubuntu
    sudo apt-get update
    sudo apt-get install -y build-essential
    sudo apt-get install -y wget
    sudo apt-get install -y pkg-config
    sudo apt-get install -y python3-venv

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
        echo "TA-Lib source already downloaded."
    fi
elif [ -f /etc/redhat-release ]; then
    # CentOS/RHEL
    sudo yum groupinstall -y "Development Tools"
    sudo yum install -y wget
    sudo yum install -y python3-venv

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
        echo "TA-Lib source already downloaded."
    fi
else
    echo "Unsupported OS. Please install TA-Lib manually according to your OS instructions."
    echo "See: https://github.com/mrjbq7/ta-lib#dependencies"
    exit 1
fi

# Update LD_LIBRARY_PATH to find the TA-Lib library
export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

# Create and activate virtual environment
echo "Creating virtual environment..."
python3 -m venv venv
echo "Activating virtual environment..."
source venv/bin/activate

# Install Python packages in the virtual environment
echo "Installing Python requirements in virtual environment..."
pip install --upgrade pip
pip install wheel
pip install -r requirements.txt

echo "Installation complete! All packages have been installed in a virtual environment."
echo "To activate the virtual environment in the future, run: source venv/bin/activate"
echo "To deactivate when you're done, run: deactivate"