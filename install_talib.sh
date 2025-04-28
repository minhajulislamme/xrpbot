#!/bin/bash

# Enhanced script to install TA-Lib on Digital Ocean VPS
# This fixes linking issues with the ta-lib library

echo "============================================================"
echo "Installing TA-Lib and all requirements"
echo "============================================================"

# Step 1: Install build dependencies
echo "Step 1: Installing build dependencies..."
sudo apt-get update && sudo apt-get install -y build-essential wget tar python3-dev pkg-config || {
    echo "Failed to install build dependencies.";
    exit 1;
}

# Step 2: Download and install TA-Lib C library
echo "Step 2: Downloading and installing TA-Lib C library..."
TA_LIB_VERSION="0.4.0"
TA_LIB_URL="https://sourceforge.net/projects/ta-lib/files/ta-lib/${TA_LIB_VERSION}/ta-lib-${TA_LIB_VERSION}-src.tar.gz"
TEMP_DIR="/tmp/ta-lib-install"

# Clean any previous installation attempts
if [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
fi

mkdir -p "$TEMP_DIR" && cd "$TEMP_DIR" || {
    echo "Failed to create temporary directory.";
    exit 1;
}

echo "Downloading TA-Lib source..."
wget -O ta-lib-src.tar.gz "$TA_LIB_URL" || {
    echo "Failed to download TA-Lib source.";
    exit 1;
}

echo "Extracting TA-Lib source..."
tar -xzf ta-lib-src.tar.gz || {
    echo "Failed to extract TA-Lib source.";
    exit 1;
}

# Check which directory was created
if [ -d "ta-lib" ]; then
    echo "Using extracted directory: ta-lib"
    cd ta-lib || exit 1
elif [ -d "ta-lib-$TA_LIB_VERSION" ]; then
    echo "Using extracted directory: ta-lib-$TA_LIB_VERSION"
    cd "ta-lib-$TA_LIB_VERSION" || exit 1
else
    echo "Error: Could not find extracted TA-Lib directory!"
    ls -la
    exit 1;
fi

echo "Configuring and building TA-Lib..."
# Using default install location that works better with linkers
./configure && make && sudo make install || {
    echo "Failed to build and install TA-Lib C library.";
    exit 1;
}

# Update the dynamic linker and create required symlinks
echo "Updating dynamic linker..."
sudo ldconfig || {
    echo "Failed to update dynamic linker.";
    exit 1;
}

# Ensure library can be found by creating symlinks if needed
echo "Creating additional symlinks to ensure library is found..."
if [ -f "/usr/local/lib/libta_lib.a" ] && [ ! -f "/usr/lib/libta_lib.a" ]; then
    sudo ln -s /usr/local/lib/libta_lib.a /usr/lib/libta_lib.a
fi

if [ -f "/usr/local/lib/libta_lib.la" ] && [ ! -f "/usr/lib/libta_lib.la" ]; then
    sudo ln -s /usr/local/lib/libta_lib.la /usr/lib/libta_lib.la
fi

if [ -f "/usr/local/lib/libta_lib.so" ] && [ ! -f "/usr/lib/libta_lib.so" ]; then
    sudo ln -s /usr/local/lib/libta_lib.so /usr/lib/libta_lib.so
fi

# Export the library path to make sure the installer can find it
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib

# Step 3: Install TA-Lib Python wrapper
echo "Step 3: Installing TA-Lib Python wrapper..."
pip install --no-cache-dir ta-lib || {
    # If direct install fails, try using pip with include and library paths specified
    echo "Direct installation failed, trying with explicit library paths..."
    TALIB_INCLUDE=/usr/local/include TALIB_LIBRARY=/usr/local/lib pip install --no-cache-dir ta-lib || {
        echo "Failed to install TA-Lib Python wrapper.";
        exit 1;
    }
}

# Step 4: Install all requirements from requirements.txt
echo "Step 4: Installing requirements from requirements.txt..."
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REQ_FILE="${SCRIPT_DIR}/requirements.txt"

if [ -f "$REQ_FILE" ]; then
    echo "Installing packages from requirements.txt..."
    grep -v "ta-lib" "$REQ_FILE" > "$TEMP_DIR/temp_requirements.txt"
    pip install -r "$TEMP_DIR/temp_requirements.txt" || {
        echo "Failed to install requirements from requirements.txt.";
        exit 1;
    }
else
    echo "requirements.txt not found. Skipping requirements installation."
fi

# Cleanup
echo "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"

echo "============================================================"
echo "Installation completed successfully!"
echo "============================================================"