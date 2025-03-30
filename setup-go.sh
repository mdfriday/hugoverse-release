#!/bin/bash
set -e

# Default Go version
GO_VERSION=${GO_VERSION:-1.21.7}

# Detect the system architecture
ARCH=$(dpkg --print-architecture)
TARGET_ARCH=${TARGETARCH:-$ARCH}

echo "Setting up Go $GO_VERSION for host architecture: $ARCH, target architecture: $TARGET_ARCH"

# Download and install Go
GO_TAR="go${GO_VERSION}.linux-${ARCH}.tar.gz"
wget --no-check-certificate --progress=dot:mega https://dl.google.com/go/${GO_TAR}
tar -C /usr/local -xzf ${GO_TAR}
rm ${GO_TAR}

# Set up Go environment
export PATH=$PATH:/usr/local/go/bin
export GOPATH=/go
mkdir -p $GOPATH/src $GOPATH/bin $GOPATH/pkg

# Add Go to global path
echo "export PATH=\$PATH:/usr/local/go/bin" >> /etc/profile
echo "export GOPATH=/go" >> /etc/profile
echo "export PATH=\$PATH:\$GOPATH/bin" >> /etc/profile

# Also add to .bashrc for non-login shells
echo "export PATH=\$PATH:/usr/local/go/bin" >> /root/.bashrc
echo "export GOPATH=/go" >> /root/.bashrc
echo "export PATH=\$PATH:\$GOPATH/bin" >> /root/.bashrc

# Add Go PATH to system-wide environment
echo "/usr/local/go/bin" > /etc/paths.d/go

# Create symlink for the go binary
ln -sf /usr/local/go/bin/go /usr/local/bin/go
ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt

# Verify installation
go version

# Set default build environment
export CGO_ENABLED=1

# Provide environment info for debugging
echo "Go environment:"
go env

# Verify cross-compilation setup
if [ "$TARGET_ARCH" = "arm64" ] && [ "$ARCH" != "arm64" ]; then
  echo "Verifying ARM64 cross-compilation setup..."
  
  # Verify cross-compilation toolchain
  if command -v aarch64-linux-gnu-gcc &> /dev/null; then
    echo "Cross-compiler version:"
    aarch64-linux-gnu-gcc --version
  else
    echo "WARNING: aarch64-linux-gnu-gcc not found. ARM64 cross-compilation will likely fail."
  fi
  
  # Verify pkg-config setup for ARM64
  if [ -d "/usr/lib/aarch64-linux-gnu/pkgconfig" ]; then
    echo "ARM64 pkg-config directory exists."
    
    # Check if vips.pc exists for ARM64
    if [ -f "/usr/lib/aarch64-linux-gnu/pkgconfig/vips.pc" ]; then
      echo "ARM64 libvips pkg-config file found."
    else
      echo "WARNING: ARM64 libvips pkg-config file not found."
    fi
  else
    echo "WARNING: ARM64 pkg-config directory not found."
  fi
  
  # Test pkg-config for ARM64
  echo "Testing pkg-config for ARM64 libvips:"
  PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig pkg-config --libs vips || \
    echo "WARNING: pkg-config failed to find libvips for ARM64."
fi

# Export PATH in a file that can be sourced by other scripts
cat > /go.env << EOF
export PATH=$PATH:/usr/local/go/bin
export GOPATH=/go
export PATH=$PATH:$GOPATH/bin
export CGO_ENABLED=1
EOF

echo "Go setup complete!"
