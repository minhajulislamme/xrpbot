#!/bin/bash

echo "Installing TA-Lib dependencies..."
sudo apt-get update
sudo apt-get install -y build-essential wget

# Download and install TA-Lib
cd /tmp
wget http://prdownloads.sourceforge.net/ta-lib/ta-lib-0.4.0-src.tar.gz
tar -xzf ta-lib-0.4.0-src.tar.gz
cd ta-lib/
./configure --prefix=/usr
make
sudo make install

# Clean up
cd ..
rm -rf ta-lib-0.4.0-src.tar.gz ta-lib

echo "Installing Python requirements..."
cd $HOME/binancebot
pip install -r requirements.txt

echo "TA-Lib installation completed!"