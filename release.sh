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
    
    # Use the build-arm64.sh script which sets all the necessary environment variables
    /usr/local/bin/build-arm64.sh go build -o ${output_path} -ldflags "${ldflags}" .
    
    # Check if build was successful
    if [ $? -ne 0 ]; then
      echo "ARM64 build failed. Check cross-compilation setup and dependencies."
      return 1
    fi
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
  build_for_arch "$TARGET_ARCH" || exit 1
else
  # Build for amd64 first
  build_for_arch "amd64" || exit 1
  
  # Try building for arm64 if amd64 succeeded
  echo "Attempting ARM64 build..."
  if build_for_arch "arm64"; then
    echo "ARM64 build successful"
  else
    echo "ARM64 build failed, but amd64 build was successful. Continuing..."
  fi
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
