#!/bin/bash

# Update package list and install required dependencies
sudo apt update
sudo apt install -y build-essential zlib1g-dev

# Download OpenSSL 1.1.1f
wget https://www.openssl.org/source/openssl-1.1.1f.tar.gz

# Extract the tarball
tar -xzvf openssl-1.1.1f.tar.gz

# Navigate to the extracted directory
cd openssl-1.1.1f

# Configure and install OpenSSL
./config --prefix=/usr/local/ssl --openssldir=/usr/local/ssl shared zlib
make
sudo make install

# Create symbolic links to the new installation
sudo ln -sf /usr/local/ssl/bin/openssl /usr/bin/openssl
sudo ln -sf /usr/local/ssl/include/openssl /usr/include/openssl
sudo ln -sf /usr/local/ssl/lib/libcrypto.so.1.1 /usr/lib/libcrypto.so.1.1
sudo ln -sf /usr/local/ssl/lib/libssl.so.1.1 /usr/lib/libssl.so.1.1

# Verify the installation
openssl version

# Cleanup
cd ..
rm -rf openssl-1.1.1f.tar.gz openssl-1.1.1f
