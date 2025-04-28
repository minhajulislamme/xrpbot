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
./configure --prefix=/usr && make && sudo make install || {
    echo "Failed to build and install TA-Lib C library.";
    exit 1;
}

# Update the dynamic linker and create required symlinks
echo "Updating dynamic linker..."
sudo ldconfig || {
    echo "Failed to update dynamic linker.";
    exit 1;
}

# Check if libraries exist and create symlinks with different variations
echo "Creating comprehensive symlinks to ensure library is found..."

# Check if lib exists in /usr/local/lib and create symlinks in /usr/lib
for LIB_FILE in libta_lib.a libta_lib.la libta_lib.so libta_lib.so.0 libta_lib.so.0.0.0; do
    if [ -f "/usr/local/lib/$LIB_FILE" ]; then
        echo "Found $LIB_FILE in /usr/local/lib, creating symlink in /usr/lib"
        sudo ln -sf /usr/local/lib/$LIB_FILE /usr/lib/$LIB_FILE
    fi
done

# Check if lib exists in /usr/lib and create symlinks in /usr/local/lib
for LIB_FILE in libta_lib.a libta_lib.la libta_lib.so libta_lib.so.0 libta_lib.so.0.0.0; do
    if [ -f "/usr/lib/$LIB_FILE" ] && [ ! -f "/usr/local/lib/$LIB_FILE" ]; then
        echo "Found $LIB_FILE in /usr/lib, creating symlink in /usr/local/lib"
        sudo ln -sf /usr/lib/$LIB_FILE /usr/local/lib/$LIB_FILE
    fi
done

# Create symlinks for libta-lib (with dash) as some builds look for this naming
if [ -f "/usr/local/lib/libta_lib.so" ]; then
    echo "Creating libta-lib.so symlinks..."
    sudo ln -sf /usr/local/lib/libta_lib.so /usr/lib/libta-lib.so
    sudo ln -sf /usr/local/lib/libta_lib.so /usr/local/lib/libta-lib.so
fi

if [ -f "/usr/local/lib/libta_lib.a" ]; then
    echo "Creating libta-lib.a symlinks..."
    sudo ln -sf /usr/local/lib/libta_lib.a /usr/lib/libta-lib.a 
    sudo ln -sf /usr/local/lib/libta_lib.a /usr/local/lib/libta-lib.a
fi

# Export the library paths to make sure the installer can find it
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib:/usr/lib
export LIBRARY_PATH=$LIBRARY_PATH:/usr/local/lib:/usr/lib
export C_INCLUDE_PATH=$C_INCLUDE_PATH:/usr/local/include:/usr/include
export CPLUS_INCLUDE_PATH=$CPLUS_INCLUDE_PATH:/usr/local/include:/usr/include

# Step 3: Install TA-Lib Python wrapper with detailed error reporting
echo "Step 3: Installing TA-Lib Python wrapper..."

# Try multiple installation methods
echo "Method 1: Direct pip install with no cache..."
pip install --verbose --no-cache-dir ta-lib || {
    echo "Method 1 failed, trying Method 2: Using environment variables..."
    TALIB_INCLUDE=/usr/local/include TALIB_LIBRARY=/usr/local/lib pip install --verbose --no-cache-dir ta-lib || {
        echo "Method 2 failed, trying Method 3: Installing from source..."
        
        # Try installing from source
        cd "$TEMP_DIR"
        echo "Downloading TA-Lib Python wrapper source..."
        pip download --no-binary :all: --no-deps ta-lib
        
        # Extract and build
        tar -xf ta-lib-*.tar.gz
        cd ta-lib-*/
        
        # Edit setup.py to explicitly specify include_dirs and library_dirs
        if [ -f "setup.py" ]; then
            echo "Modifying setup.py to explicitly specify library paths..."
            # Create backup of original setup.py
            cp setup.py setup.py.bak
            
            # Modify setup.py to add include and library directories
            sed -i 's/Extension(/Extension(\n    include_dirs=[\/usr\/local\/include, \/usr\/include],\n    library_dirs=[\/usr\/local\/lib, \/usr\/lib],\n    /' setup.py || echo "Failed to modify setup.py, continuing anyway..."
        fi
        
        # Build and install
        TALIB_INCLUDE=/usr/local/include TALIB_LIBRARY=/usr/local/lib LDFLAGS="-L/usr/local/lib -L/usr/lib" CFLAGS="-I/usr/local/include -I/usr/include" python setup.py build_ext --include-dirs=/usr/local/include:/usr/include --library-dirs=/usr/local/lib:/usr/lib install || {
            echo "All methods failed to install TA-Lib Python wrapper.";
            exit 1;
        }
    }
}

# Check if installation was successful
if python3 -c "import talib" 2>/dev/null; then
    echo "✅ TA-Lib Python wrapper installed successfully!"
else
    echo "❌ TA-Lib installation verification failed. The module could not be imported."
    exit 1
fi

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