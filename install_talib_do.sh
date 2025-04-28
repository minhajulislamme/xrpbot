#!/bin/bash

# Digital Ocean VPS Optimized TA-Lib Installation Script
# This script is specifically designed to fix the "-lta-lib not found" error

set -e  # Exit immediately if a command exits with non-zero status

echo "============================================================"
echo "Digital Ocean VPS Optimized TA-Lib Installation"
echo "============================================================"

# Install system dependencies
echo "Step 1: Installing required dependencies..."
sudo apt-get update
sudo apt-get install -y build-essential wget pkg-config cmake python3-dev python3-pip

# Create a temporary directory
TEMP_DIR=$(mktemp -d)
echo "Working in temporary directory: $TEMP_DIR"
cd "$TEMP_DIR"

# Download, build and install TA-Lib from source
echo "Step 2: Building TA-Lib from source..."
wget http://prdownloads.sourceforge.net/ta-lib/ta-lib-0.4.0-src.tar.gz
tar -xzf ta-lib-0.4.0-src.tar.gz
cd ta-lib/

# Configure and install to /usr to match linker expectations
echo "Configuring and building TA-Lib..."
./configure --prefix=/usr
make
sudo make install

# Create essential symlinks to fix "-lta-lib not found" error
echo "Creating critical symlinks for linker..."
# The critical symlink is usually from libta_lib.so.0 to libta-lib.so
if [ -f "/usr/lib/libta_lib.so.0" ]; then
    sudo ln -sf /usr/lib/libta_lib.so.0 /usr/lib/libta-lib.so
fi

# Add more symlinks to ensure libraries are found
if [ -f "/usr/lib/libta_lib.so" ]; then
    sudo ln -sf /usr/lib/libta_lib.so /usr/lib/libta-lib.so
fi

if [ -f "/usr/lib/libta_lib.a" ]; then
    sudo ln -sf /usr/lib/libta_lib.a /usr/lib/libta-lib.a
fi

# Update dynamic linker cache
echo "Updating dynamic linker cache..."
sudo ldconfig

# Return to the temporary directory
cd "$TEMP_DIR"

echo "Step 3: Installing NumPy first (required dependency for TA-Lib)..."
pip install numpy

echo "Step 4: Installing TA-Lib Python wrapper with fixed library paths..."

# Set environment variables to help installation process find the library
export TA_LIBRARY_PATH=/usr/lib
export TA_INCLUDE_PATH=/usr/include

# Try direct installation with environment variables
echo "Installing TA-Lib Python wrapper..."
LIBRARY_PATH=/usr/lib LD_LIBRARY_PATH=/usr/lib C_INCLUDE_PATH=/usr/include pip install --no-cache-dir ta-lib

# Verify the installation
echo "Verifying TA-Lib installation..."
if python3 -c "import talib; print('TA-Lib installed successfully!')" 2>/dev/null; then
    echo "✅ TA-Lib verified and working correctly!"
else
    echo "❌ TA-Lib verification failed. Trying alternative approach..."
    
    # If it fails, try installing from GitHub with specific paths
    pip install --no-cache-dir git+https://github.com/mrjbq7/ta-lib.git@master
    
    # Verify again
    if python3 -c "import talib; print('TA-Lib installed successfully!')" 2>/dev/null; then
        echo "✅ TA-Lib verified and working correctly using GitHub version!"
    else
        echo "❌ All TA-Lib installation attempts failed."
        echo "Trying alternative 'ta' package which doesn't require C libraries..."
        pip install --no-cache-dir ta
        echo "Note: You may need to modify your code to use 'ta' instead of 'talib'."
        exit 1
    fi
fi

# Clean up
cd ~
rm -rf "$TEMP_DIR"

echo "============================================================"
echo "TA-Lib installation complete!"
echo "============================================================"