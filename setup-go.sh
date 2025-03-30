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

# Verify installation
go version

# Set default build environment
export CGO_ENABLED=1

# Provide environment info for debugging
echo "Go environment:"
go env

# Set up architecture-specific environment for cross-compilation
if [ "$TARGET_ARCH" = "arm64" ] && [ "$ARCH" != "arm64" ]; then
  echo "Setting up cross-compilation environment for ARM64..."
  
  # Set environment variables for ARM64 cross-compilation
  export CGO_ENABLED=1
  export CC=aarch64-linux-gnu-gcc
  export CXX=aarch64-linux-gnu-g++
  export PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig
  
  # Verify cross-compilation toolchain
  echo "Cross-compiler version:"
  $CC --version
  
  # Create a global environment file that can be sourced by other scripts
  cat > /arm64.env << EOF
export CGO_ENABLED=1
export GOOS=linux
export GOARCH=arm64
export CC=aarch64-linux-gnu-gcc
export CXX=aarch64-linux-gnu-g++
export PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig
EOF
fi

echo "Go setup complete!"
