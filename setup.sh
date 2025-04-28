#!/bin/bash

# Script to set up a virtual environment and install all requirements for the Binance bot
# including TA-Lib which requires special handling

# Exit on any error
set -e

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
echo "Creating virtual environment..."
python3 -m venv venv
echo "Activating virtual environment..."
source venv/bin/activate

# Install Python packages in the virtual environment
echo "Installing Python requirements in virtual environment..."
pip install --upgrade pip setuptools wheel

# Install TA-Lib Python wrapper specifically before other requirements
echo "Installing TA-Lib Python wrapper..."
export TA_LIBRARY_PATH=/usr/lib
export TA_INCLUDE_PATH=/usr/include
pip install numpy
pip install --no-binary :all: ta-lib

# Install other dependencies
echo "Installing remaining Python requirements..."
# Use system-provided cmake instead of letting pip build it
pip install --upgrade cmake

# Install remaining requirements
pip install -r requirements.txt

echo "Installation complete! All packages have been installed in a virtual environment."
echo "To activate the virtual environment in the future, run: source venv/bin/activate"
echo "To deactivate when you're done, run: deactivate"