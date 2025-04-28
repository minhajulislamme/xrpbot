#!/bin/bash

# Script to uninstall TA-Lib and all requirements
echo "============================================================"
echo "Uninstalling TA-Lib and all requirements"
echo "============================================================"

# Function to handle errors
handle_error() {
    echo "ERROR: $1"
    echo "Some packages may not have been completely removed."
    exit 1
}

# Get the requirements from requirements.txt
echo "Step 1: Reading requirements to uninstall..."
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REQ_FILE="${SCRIPT_DIR}/requirements.txt"

if [ -f "$REQ_FILE" ]; then
    # Store requirements in an array
    mapfile -t REQUIREMENTS < "$REQ_FILE"
    echo "Found $(wc -l < "$REQ_FILE") packages to uninstall in requirements.txt"
else
    echo "requirements.txt not found. Will only uninstall TA-Lib."
    REQUIREMENTS=()
fi

# Step 2: Uninstall TA-Lib first (both the Python wrapper and C library)
echo "Step 2: Uninstalling TA-Lib Python wrapper..."
pip uninstall -y ta-lib || echo "Warning: Failed to uninstall ta-lib Python package. May not be installed."

# Step 3: Uninstall all other requirements
echo "Step 3: Uninstalling other requirements..."
for req in "${REQUIREMENTS[@]}"; do
    # Skip empty lines and comments
    if [[ -z "$req" || "$req" == \#* ]]; then
        continue
    fi
    
    # Extract package name (remove version specifiers)
    PACKAGE=$(echo "$req" | cut -d'=' -f1 | cut -d'>' -f1 | cut -d'<' -f1 | tr -d ' ')
    
    # Skip ta-lib as we already handled it
    if [[ "$PACKAGE" == "ta-lib" || "$PACKAGE" == "TA-Lib" ]]; then
        continue
    fi
    
    echo "Uninstalling $PACKAGE..."
    pip uninstall -y "$PACKAGE" || echo "Warning: Failed to uninstall $PACKAGE. May not be installed or required by system."
done

# Remove the compiled library files if they exist
echo "Step 4: Removing TA-Lib C library..."
if [ -f "/usr/lib/libta_lib.so.0.0.0" ]; then
    sudo rm -f /usr/lib/libta_lib.so* || echo "Warning: Failed to remove TA-Lib C library files."
    sudo rm -f /usr/lib/libta_lib.* || echo "Warning: Failed to remove some TA-Lib C library files."
    sudo rm -rf /usr/include/ta-lib/ || echo "Warning: Failed to remove TA-Lib include files."
    
    # Update the dynamic linker
    sudo ldconfig || echo "Warning: ldconfig failed but continuing anyway."
    
    echo "TA-Lib C library removed."
else
    echo "TA-Lib C library files not found. Skipping removal."
fi

echo "============================================================"
echo "Uninstallation completed!"
echo "Note: System packages and dependencies required by other applications were not removed."
echo "============================================================"