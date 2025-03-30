#!/bin/bash
set -e

# Initialize variables
PROJECT_NAME=${PROJECT_NAME:-hugoverse}
VERSION=${VERSION:-$(date +%Y%m%d)}
GITHUB_TOKEN=${GITHUB_TOKEN:-}
GITHUB_REPO=${GITHUB_REPO:-}

# Host architecture information
HOST_ARCH=$(dpkg --print-architecture)
BUILD_DIR="build-artifacts"
mkdir -p ${BUILD_DIR}

echo "Starting release process for ${PROJECT_NAME} v${VERSION}"

# Function to build for a specific architecture
build_for_arch() {
  local arch=$1
  local output_name="${PROJECT_NAME}-linux-${arch}"
  local output_path="${BUILD_DIR}/${output_name}"
  local ldflags="-s -w -X main.Version=${VERSION}"
  
  echo "Building for ${arch} architecture..."
  
  # Set up architecture-specific environment
  if [ "$arch" = "arm64" ] && [ "$HOST_ARCH" != "arm64" ]; then
    echo "Using cross-compilation for ARM64..."
    if [ -f "/arm64.env" ]; then
      source /arm64.env
    fi
    
    # Build with ARM64-specific flags
    GOOS=linux GOARCH=arm64 CGO_ENABLED=1 \
      CC=aarch64-linux-gnu-gcc \
      CXX=aarch64-linux-gnu-g++ \
      PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig \
      go build -o ${output_path} -ldflags "${ldflags}" .
  else
    # Build for the host architecture
    GOOS=linux GOARCH=${arch} CGO_ENABLED=1 \
      go build -o ${output_path} -ldflags "${ldflags}" .
  fi
  
  echo "Build complete: ${output_path}"
  
  # Compress with UPX if available
  if command -v upx &> /dev/null; then
    echo "Compressing with UPX..."
    upx -9 ${output_path}
  fi
  
  # Create ZIP archive
  zip -j ${output_path}.zip ${output_path}
  echo "Created archive: ${output_path}.zip"
  
  return 0
}

# Build for specified architectures
if [ -n "$TARGET_ARCH" ]; then
  # Build for specific target architecture
  build_for_arch "$TARGET_ARCH"
else
  # Build for both amd64 and arm64
  build_for_arch "amd64"
  build_for_arch "arm64"
fi

# Upload to GitHub if token and repo are provided
if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
  echo "Uploading artifacts to GitHub..."
  
  for artifact in ${BUILD_DIR}/${PROJECT_NAME}-linux-*.zip; do
    echo "Uploading: $artifact"
    github-assets-uploader \
      -token ${GITHUB_TOKEN} \
      -repo ${GITHUB_REPO} \
      -tag ${VERSION} \
      -file ${artifact} \
      -name $(basename ${artifact})
  done
  
  echo "Upload complete!"
else
  echo "Skipping GitHub upload: GITHUB_TOKEN or GITHUB_REPO not set"
fi

echo "Release process completed successfully!"
