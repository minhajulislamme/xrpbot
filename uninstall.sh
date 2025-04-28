#!/bin/bash

# Script to uninstall all Binance bot components that were installed globally
# including TA-Lib and all Python packages

# Exit on any error
set -e

echo "Uninstalling Binance Bot components..."

# Read requirements.txt and uninstall each package
if [ -f "requirements.txt" ]; then
    echo "Uninstalling Python packages..."
    while read -r package; do
        # Skip commented lines and empty lines
        if [[ ! $package =~ ^#.*$ && ! -z $package ]]; then
            # Extract just the package name (before any version specifier)
            pkg_name=$(echo "$package" | sed -E 's/([a-zA-Z0-9_-]+)(.*)/\1/')
            echo "Uninstalling $pkg_name..."
            sudo pip uninstall -y "$pkg_name"
        fi
    done < requirements.txt
else
    echo "requirements.txt not found. Skipping Python package uninstallation."
fi

# Uninstall TA-Lib library
echo "Removing TA-Lib library..."
if [ -d "ta-lib" ]; then
    cd ta-lib
    if [ -f "Makefile" ]; then
        sudo make uninstall
    fi
    cd ..
    echo "Removing TA-Lib source files..."
    rm -rf ta-lib
    rm -f ta-lib-0.4.0-src.tar.gz
else
    echo "TA-Lib directory not found. It may have been already removed."
fi

# Clean up any potential leftover files
echo "Cleaning up..."
if [ -f "ta-lib-0.4.0-src.tar.gz" ]; then
    rm -f ta-lib-0.4.0-src.tar.gz
fi

echo "Uninstallation complete! All Binance bot components have been removed."