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
PROJECT_PATH=${PROJECT_PATH:-$INPUT_PROJECT_PATH}
PROJECT_PATH=${PROJECT_PATH:-.}
BINARY_NAME=${BINARY_NAME:-$INPUT_BINARY_NAME}
BINARY_NAME=${BINARY_NAME:-$PROJECT_NAME}

# Debug information
echo "Environment variables:"
echo "GITHUB_TOKEN: ${GITHUB_TOKEN:+<set but hidden>}"
echo "GITHUB_REPO: ${GITHUB_REPO}"
echo "VERSION: ${VERSION}"
echo "GOOS: ${GOOS}"
echo "GOARCH: ${GOARCH}"
echo "EXTRA_FILES: ${EXTRA_FILES}"
echo "PROJECT_PATH: ${PROJECT_PATH}"
echo "BINARY_NAME: ${BINARY_NAME}"

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

# Make sure BUILD_DIR is absolute
if [ "${BUILD_DIR:0:1}" != "/" ]; then
  # If relative path, make it absolute from current directory
  BUILD_DIR="$(pwd)/${BUILD_DIR:-build-artifacts}"
fi
mkdir -p ${BUILD_DIR}
echo "Build directory: ${BUILD_DIR}"

# Host architecture information
HOST_ARCH=$(dpkg --print-architecture)

echo "Starting release process for ${PROJECT_NAME} v${VERSION}"

# Check if this is a multi-binary build
if [[ "$PROJECT_PATH" == *" "* ]]; then
  echo "Multi-binary build detected!"
  MULTI_BINARY=true
  
  # Split project path into array
  IFS=' ' read -r -a PROJECT_PATHS <<< "$PROJECT_PATH"
  
  # Create a temporary directory for the build
  BUILD_WORKSPACE=$(mktemp -d)
  echo "Created temporary workspace: $BUILD_WORKSPACE"
else
  MULTI_BINARY=false
  
  # Check if the project path exists
  if [ ! -d "${PROJECT_PATH}" ]; then
    echo "Creating project directory: ${PROJECT_PATH}"
    mkdir -p "${PROJECT_PATH}"
  fi
  
  # Change to the project directory
  cd "${PROJECT_PATH}"
  echo "Current directory: $(pwd)"
fi

# Function to set up a Go module
setup_go_module() {
  local dir=$1
  local mod_name=$2
  
  if [ -d "$dir" ]; then
    cd "$dir"
    
    if ! [ -f "go.mod" ]; then
      echo "No go.mod file found in $dir. Initializing Go module..."
      go mod init "${mod_name}" || echo "Failed to initialize Go module, but continuing anyway"
    fi
    
    # Make sure all dependencies are downloaded
    if [ -f "go.mod" ]; then
      echo "Downloading dependencies for $dir..."
      go mod tidy || echo "go mod tidy failed, but continuing anyway"
      go mod download || echo "go mod download failed, but continuing anyway"
    fi
  else
    echo "Directory $dir does not exist, skipping Go module setup"
  fi
}

# Create default files if they don't exist but are in EXTRA_FILES
create_extra_files() {
  local dir=$1
  
  if [ -d "$dir" ]; then
    cd "$dir"
    
    if [[ "$EXTRA_FILES" == *"LICENSE"* ]] && [ ! -f "LICENSE" ]; then
      echo "Creating default LICENSE file in $dir..."
      cat > LICENSE << EOF
MIT License

Copyright (c) $(date +%Y) MDFriday

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
      echo "Created LICENSE file"
    fi

    if [[ "$EXTRA_FILES" == *"README.md"* ]] && [ ! -f "README.md" ]; then
      echo "Creating default README.md file in $dir..."
      cat > README.md << EOF
# ${BINARY_NAME}

This is an auto-generated README file for ${BINARY_NAME}.

## Usage

\`\`\`
./${BINARY_NAME} 
\`\`\`

## License

See the LICENSE file for details.
EOF
      echo "Created README.md file"
    fi

    if [[ "$EXTRA_FILES" == *"manifest.json"* ]] && [ ! -f "manifest.json" ]; then
      echo "Creating default manifest.json file in $dir..."
      cat > manifest.json << EOF
{
  "name": "${BINARY_NAME}",
  "version": "${VERSION}",
  "description": "Generated by hugoverse-release action",
  "arch": "${GOARCH}",
  "os": "${GOOS}"
}
EOF
      echo "Created manifest.json file"
    fi
  else
    echo "Directory $dir does not exist, skipping extra files creation"
  fi
}

# Create a simple main.go file if it doesn't exist
create_main_go() {
  local dir=$1
  local binary=$2
  
  if [ -d "$dir" ]; then
    cd "$dir"
    
    if ! [ -f "main.go" ] && ! ls *.go 1> /dev/null 2>&1; then
      echo "No Go files found in $dir. Creating a simple main.go file..."
      cat > main.go << EOF
package main

import (
	"fmt"
	"os"
	"runtime"
)

var Version = "dev"

func main() {
	fmt.Printf("${binary} version %s (%s/%s)\n", Version, runtime.GOOS, runtime.GOARCH)
	os.Exit(0)
}
EOF
      echo "Created main.go in $dir"
    fi
  else
    echo "Directory $dir does not exist, skipping main.go creation"
  fi
}

# Handle multi-binary builds
if [ "$MULTI_BINARY" = true ]; then
  echo "Setting up multiple binary builds..."
  
  # Create build directory for each binary
  for i in "${!PROJECT_PATHS[@]}"; do
    path="${PROJECT_PATHS[$i]}"
    # Derive binary name from directory if not specified
    if [ "$BINARY_NAME" = "$PROJECT_NAME" ]; then
      binary_name=$(basename "$path")
    else
      binary_name="${BINARY_NAME}-$(basename "$path")"
    fi
    
    echo "Setting up build for $binary_name from $path"
    
    # Create directory if it doesn't exist
    if [ ! -d "$path" ]; then
      echo "Creating directory: $path"
      mkdir -p "$path"
    fi
    
    # Setup Go module and create necessary files
    setup_go_module "$path" "$binary_name"
    create_extra_files "$path"
    create_main_go "$path" "$binary_name"
    
    # Build the binary
    build_for_arch "$GOARCH" "$path" "$binary_name" || {
      echo "Failed to build $binary_name from $path"
      continue
    }
  done
else
  # Handle single binary build
  setup_go_module "$PROJECT_PATH" "$BINARY_NAME"
  create_extra_files "$PROJECT_PATH"
  create_main_go "$PROJECT_PATH" "$BINARY_NAME"
  
  # Build for specified architectures
  if [ -n "$GOARCH" ]; then
    # Build for specific target architecture from GitHub Actions
    echo "Using architecture from GitHub Actions: $GOARCH"
    build_for_arch "$GOARCH" "$PROJECT_PATH" "$BINARY_NAME" || exit 1
  elif [ -n "$TARGET_ARCH" ]; then
    # Build for specific target architecture from environment
    build_for_arch "$TARGET_ARCH" "$PROJECT_PATH" "$BINARY_NAME" || exit 1
  else
    # Build for amd64 first
    build_for_arch "amd64" "$PROJECT_PATH" "$BINARY_NAME" || exit 1
    
    # Try building for arm64 if amd64 succeeded
    echo "Attempting ARM64 build..."
    if build_for_arch "arm64" "$PROJECT_PATH" "$BINARY_NAME"; then
      echo "ARM64 build successful"
    else
      echo "ARM64 build failed, but amd64 build was successful. Continuing..."
    fi
  fi
fi

# Function to build for a specific architecture
build_for_arch() {
  local arch=$1
  local proj_path=$2
  local bin_name=$3
  local output_name="${bin_name}-linux-${arch}"
  local output_path="${BUILD_DIR}/${output_name}"
  local ldflags="-s -w -X main.Version=${VERSION}"
  
  echo "Building for ${arch} architecture from ${proj_path}..."
  
  # Save current directory and change to project path
  local current_dir=$(pwd)
  cd "${proj_path}"
  
  # Set up architecture-specific environment
  if [ "$arch" = "arm64" ] && [ "$HOST_ARCH" != "arm64" ]; then
    echo "Using cross-compilation for ARM64..."
    
    # Make sure build-arm64.sh is executable and exists
    if [ ! -f "/usr/local/bin/build-arm64.sh" ]; then
      echo "ERROR: build-arm64.sh not found!"
      cd "$current_dir"
      return 1
    fi
    
    # Copy current Go environment to build-arm64.sh
    PATH=$PATH:/usr/local/go/bin
    
    # Use the build-arm64.sh script which sets all the necessary environment variables
    /usr/local/bin/build-arm64.sh $(which go) build -buildvcs=false -o ${output_path} -ldflags "${ldflags}" .
    
    # Check if build was successful
    if [ $? -ne 0 ]; then
      echo "ARM64 build failed. Check cross-compilation setup and dependencies."
      cd "$current_dir"
      return 1
    fi
  else
    # Build for the host architecture
    echo "Running: GOOS=linux GOARCH=${arch} CGO_ENABLED=1 go build -buildvcs=false -o ${output_path} -ldflags \"${ldflags}\" ."
    GOOS=linux GOARCH=${arch} CGO_ENABLED=1 \
      go build -buildvcs=false -o ${output_path} -ldflags "${ldflags}" .
  fi
  
  # Restore original directory
  cd "$current_dir"
  
  echo "Build complete: ${output_path}"
  
  # Check if the built file exists
  if [ ! -f "${output_path}" ]; then
    echo "ERROR: Build failed, output file ${output_path} not found."
    
    # Try to find what was actually built
    echo "Searching for built executables in ${BUILD_DIR}:"
    find ${BUILD_DIR} -type f -executable || echo "No executables found"
    
    return 1
  fi
  
  # Compress with UPX if available
  if command -v upx &> /dev/null; then
    echo "Compressing with UPX..."
    upx -9 ${output_path} || echo "UPX compression failed, continuing without compression"
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
  (cd ${BUILD_DIR} && zip -j ${output_name}.zip ${output_name} $(for file in $EXTRA_FILES; do if [ -f "${BUILD_DIR}/$(basename $file)" ]; then echo "$(basename $file)"; fi; done))
  echo "Created archive: ${BUILD_DIR}/${output_name}.zip"
  
  return 0
}

# Upload to GitHub if token and repo are provided
if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
  echo "Preparing to upload artifacts to GitHub repository: $GITHUB_REPO"
  
  # First, check if the release exists
  echo "Checking if release ${VERSION} exists..."
  RELEASE_EXISTS=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${VERSION}")
  
  if [ "$RELEASE_EXISTS" = "404" ]; then
    echo "Release ${VERSION} does not exist. Creating it now..."
    RELEASE_DATA="{\"tag_name\":\"${VERSION}\",\"name\":\"${BINARY_NAME} ${VERSION}\",\"body\":\"Automated release of ${BINARY_NAME} ${VERSION}\",\"draft\":false,\"prerelease\":false}"
    
    RELEASE_RESPONSE=$(curl -s -X POST \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "${RELEASE_DATA}" \
      "https://api.github.com/repos/${GITHUB_REPO}/releases")
    
    # Extract release ID from the response
    RELEASE_ID=$(echo "$RELEASE_RESPONSE" | grep -o '"id": [0-9]*' | head -1 | grep -o '[0-9]*')
    
    if [ -z "$RELEASE_ID" ]; then
      echo "Error creating release. Response: $RELEASE_RESPONSE"
      echo "Skipping upload."
      exit 1
    else
      echo "Created release with ID: $RELEASE_ID"
    fi
  else
    echo "Release ${VERSION} already exists. Continuing with upload..."
    # Get the release ID
    RELEASE_INFO=$(curl -s \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      "https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${VERSION}")
    
    RELEASE_ID=$(echo "$RELEASE_INFO" | grep -o '"id": [0-9]*' | head -1 | grep -o '[0-9]*')
    
    if [ -z "$RELEASE_ID" ]; then
      echo "Error getting release ID. Response: $RELEASE_INFO"
      echo "Skipping upload."
      exit 1
    else
      echo "Found release with ID: $RELEASE_ID"
    fi
  fi
  
  # Now upload each artifact
  for artifact in ${BUILD_DIR}/*-linux-*.zip; do
    if [ -f "$artifact" ]; then
      echo "Uploading: $artifact"
      ASSET_NAME=$(basename ${artifact})
      
      # Use curl directly to upload the asset
      UPLOAD_URL="https://uploads.github.com/repos/${GITHUB_REPO}/releases/${RELEASE_ID}/assets?name=${ASSET_NAME}"
      echo "Upload URL: $UPLOAD_URL"
      
      UPLOAD_RESPONSE=$(curl -s -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Content-Type: application/zip" \
        --data-binary @"${artifact}" \
        "${UPLOAD_URL}")
      
      if echo "$UPLOAD_RESPONSE" | grep -q '"state":"uploaded"'; then
        echo "Upload successful!"
      else
        echo "Upload failed. Response: $UPLOAD_RESPONSE"
        echo "Trying with github-assets-uploader as fallback..."
        
        # Fallback to github-assets-uploader
        github-assets-uploader \
          -logtostderr \
          -repo ${GITHUB_REPO} \
          -token ${GITHUB_TOKEN} \
          -tag ${VERSION} \
          -f ${artifact} \
          -mediatype "application/zip" || echo "Fallback upload failed too."
      fi
    else
      echo "Warning: Artifact $artifact not found, skipping upload"
    fi
  done
  
  echo "Upload process complete!"
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
