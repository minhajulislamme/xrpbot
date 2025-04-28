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
    sudo apt-get install -y python3-dev

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
    sudo yum install -y wget
    sudo yum install -y python3-venv
    sudo yum install -y python3-devel

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
pip install --upgrade pip
pip install wheel

# Install TA-Lib Python wrapper specifically before other requirements
echo "Installing TA-Lib Python wrapper..."
export TA_LIBRARY_PATH=/usr/lib
export TA_INCLUDE_PATH=/usr/include
pip install numpy
pip install --no-binary :all: ta-lib

# Install other dependencies
echo "Installing remaining Python requirements..."
pip install -r requirements.txt

echo "Installation complete! All packages have been installed in a virtual environment."
echo "To activate the virtual environment in the future, run: source venv/bin/activate"
echo "To deactivate when you're done, run: deactivate"