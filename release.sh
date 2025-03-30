#!/bin/bash
set -e

# Initialize variables
PROJECT_NAME=${PROJECT_NAME:-hugoverse}
VERSION=${VERSION:-$(date +%Y%m%d)}

# GitHub token handling - support multiple ways of passing the token
# Order of precedence: GITHUB_TOKEN -> INPUT_GITHUB_TOKEN -> REGISTRY_TOKEN
GITHUB_TOKEN=${GITHUB_TOKEN:-$INPUT_GITHUB_TOKEN}
GITHUB_TOKEN=${GITHUB_TOKEN:-$REGISTRY_TOKEN}

# Repository handling - support multiple ways of passing the repository
# Order of precedence: GITHUB_REPO -> INPUT_RELEASE_REPO -> GITHUB_REPOSITORY
GITHUB_REPO=${GITHUB_REPO:-$INPUT_RELEASE_REPO}
GITHUB_REPO=${GITHUB_REPO:-$GITHUB_REPOSITORY}

# Release tag handling
if [ -n "$INPUT_RELEASE_TAG" ]; then
  VERSION=$INPUT_RELEASE_TAG
  echo "Using release tag from GitHub Actions: $VERSION"
elif [ -n "$GITHUB_REF" ] && [[ "$GITHUB_REF" == refs/tags/* ]]; then
  # Extract tag from GITHUB_REF if it's a tag reference
  VERSION=${GITHUB_REF#refs/tags/}
  echo "Using version from GITHUB_REF tag: $VERSION"
fi

# Handle GitHub Actions input parameters
GOOS=${GOOS:-$INPUT_GOOS}
GOARCH=${GOARCH:-$INPUT_GOARCH}
EXTRA_FILES=${EXTRA_FILES:-$INPUT_EXTRA_FILES}

# Debug information
echo "Environment variables:"
echo "GITHUB_TOKEN: ${GITHUB_TOKEN:+<set but hidden>}"
echo "GITHUB_REPO: ${GITHUB_REPO}"
echo "VERSION: ${VERSION}"
echo "GOOS: ${GOOS}"
echo "GOARCH: ${GOARCH}"
echo "EXTRA_FILES: ${EXTRA_FILES}"

# Make sure Go is in the PATH
if [ ! -f "/usr/local/bin/go" ] && [ -f "/usr/local/go/bin/go" ]; then
  export PATH=$PATH:/usr/local/go/bin
  echo "Added Go to PATH: $(which go)"
fi

# Verify Go is available
if ! command -v go &> /dev/null; then
  echo "ERROR: Go command not found. Make sure Go is installed and in your PATH."
  if [ -f "/go.env" ]; then
    echo "Sourcing /go.env..."
    source /go.env
  fi
  
  # Second check after sourcing
  if ! command -v go &> /dev/null; then
    echo "ERROR: Go still not found after sourcing environment. Aborting."
    exit 1
  fi
fi

echo "Using Go version: $(go version)"

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
    
    # Make sure build-arm64.sh is executable and exists
    if [ ! -f "/usr/local/bin/build-arm64.sh" ]; then
      echo "ERROR: build-arm64.sh not found!"
      return 1
    fi
    
    # Copy current Go environment to build-arm64.sh
    PATH=$PATH:/usr/local/go/bin
    
    # Use the build-arm64.sh script which sets all the necessary environment variables
    /usr/local/bin/build-arm64.sh $(which go) build -o ${output_path} -ldflags "${ldflags}" .
    
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
  
  # Check if the built file exists
  if [ ! -f "${output_path}" ]; then
    echo "ERROR: Build failed, output file ${output_path} not found."
    return 1
  fi
  
  # Compress with UPX if available
  if command -v upx &> /dev/null; then
    echo "Compressing with UPX..."
    upx -9 ${output_path}
  fi
  
  # Copy extra files if specified
  if [ -n "$EXTRA_FILES" ]; then
    echo "Copying extra files to build directory: $EXTRA_FILES"
    for file in $EXTRA_FILES; do
      if [ -f "$file" ]; then
        cp "$file" "${BUILD_DIR}/"
        echo "Copied $file to ${BUILD_DIR}/"
      else
        echo "Warning: Extra file $file not found, skipping"
      fi
    done
  fi
  
  # Create ZIP archive
  zip -j ${output_path}.zip ${output_path} ${BUILD_DIR}/LICENSE ${BUILD_DIR}/README.md ${BUILD_DIR}/manifest.json 2>/dev/null || zip -j ${output_path}.zip ${output_path}
  echo "Created archive: ${output_path}.zip"
  
  return 0
}

# Build for specified architectures
if [ -n "$GOARCH" ]; then
  # Build for specific target architecture from GitHub Actions
  echo "Using architecture from GitHub Actions: $GOARCH"
  build_for_arch "$GOARCH" || exit 1
elif [ -n "$TARGET_ARCH" ]; then
  # Build for specific target architecture from environment
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
  echo "Uploading artifacts to GitHub repository: $GITHUB_REPO"
  
  for artifact in ${BUILD_DIR}/${PROJECT_NAME}-linux-*.zip; do
    if [ -f "$artifact" ]; then
      echo "Uploading: $artifact"
      github-assets-uploader \
        -token ${GITHUB_TOKEN} \
        -repo ${GITHUB_REPO} \
        -tag ${VERSION} \
        -file ${artifact} \
        -name $(basename ${artifact})
    else
      echo "Warning: Artifact $artifact not found, skipping upload"
    fi
  done
  
  echo "Upload complete!"
else
  echo "Skipping GitHub upload: GITHUB_TOKEN or GITHUB_REPO not set"
  echo "GITHUB_TOKEN source could be: GITHUB_TOKEN, INPUT_GITHUB_TOKEN, or REGISTRY_TOKEN"
  echo "GITHUB_REPO source could be: GITHUB_REPO, INPUT_RELEASE_REPO, or GITHUB_REPOSITORY"
  env | grep -E "GITHUB_|TOKEN" | grep -v "TOKEN.*=" || echo "No relevant environment variables found"
fi

# Set GitHub Actions output
if [ -n "$GITHUB_OUTPUT" ] && [ -d "$BUILD_DIR" ]; then
  echo "release_asset_dir=${BUILD_DIR}" >> "$GITHUB_OUTPUT"
  echo "Set output release_asset_dir=${BUILD_DIR}"
fi

echo "Release process completed successfully!"
