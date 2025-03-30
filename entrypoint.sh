#!/bin/bash
set -e

# Display basic information
echo "Starting hugoverse build process..."
echo "Architecture: $(uname -m)"
echo "Host architecture: $(dpkg --print-architecture)"

# Print all environment variables starting with INPUT_ for debugging
echo "GitHub Actions input parameters:"
env | grep "^INPUT_" || echo "No INPUT_ variables found"

# Convert GitHub Actions input variables to environment variables
if [ -n "$INPUT_GITHUB_TOKEN" ]; then
  echo "GitHub Actions detected, setting up environment variables..."
  export GITHUB_TOKEN="$INPUT_GITHUB_TOKEN"
  
  # Operating system and architecture
  if [ -n "$INPUT_GOOS" ]; then
    export GOOS="$INPUT_GOOS"
    echo "Setting GOOS=$GOOS"
  fi
  
  if [ -n "$INPUT_GOARCH" ]; then
    export GOARCH="$INPUT_GOARCH"
    export TARGET_ARCH="$INPUT_GOARCH"
    echo "Setting GOARCH=$GOARCH"
  fi
  
  # Handle extra files and release information
  if [ -n "$INPUT_EXTRA_FILES" ]; then
    export EXTRA_FILES="$INPUT_EXTRA_FILES"
    echo "Setting EXTRA_FILES=$EXTRA_FILES"
  fi
  
  if [ -n "$INPUT_VERSION" ]; then
    export VERSION="$INPUT_VERSION"
    echo "Setting VERSION=$VERSION"
  fi
  
  if [ -n "$INPUT_RELEASE_REPO" ]; then
    export GITHUB_REPO="$INPUT_RELEASE_REPO"
    echo "Setting GITHUB_REPO=$GITHUB_REPO"
  elif [ -n "$GITHUB_REPOSITORY" ]; then
    export GITHUB_REPO="$GITHUB_REPOSITORY"
    echo "Using GITHUB_REPOSITORY: $GITHUB_REPO"
  fi
  
  # Handle release tag if specified
  if [ -n "$INPUT_RELEASE_TAG" ]; then
    export VERSION="$INPUT_RELEASE_TAG"
    echo "Using release tag as version: $VERSION"
  fi
  
  # Handle project path and pre-command
  if [ -n "$INPUT_PROJECT_PATH" ]; then
    export PROJECT_PATH="$INPUT_PROJECT_PATH"
    echo "Setting PROJECT_PATH=$PROJECT_PATH"
  fi
  
  if [ -n "$INPUT_PRE_COMMAND" ]; then
    export PRE_COMMAND="$INPUT_PRE_COMMAND"
    echo "Setting PRE_COMMAND=$PRE_COMMAND"
  fi
  
  echo "Environment setup complete"
fi

# Run setup for Go
if [ -f "/setup-go.sh" ]; then
  echo "Setting up Go environment..."
  source /setup-go.sh
else
  echo "Error: setup-go.sh not found!"
  exit 1
fi

# Ensure Go is in the PATH
if [ -f "/go.env" ]; then
  source /go.env
fi

# Verify Go is available
echo "Verifying Go installation:"
which go || echo "ERROR: Go not found in PATH after setup!"
go version || echo "ERROR: Go command failed after setup!"

# Execute pre-command if provided
if [ -n "$PRE_COMMAND" ]; then
  echo "Executing pre-command: $PRE_COMMAND"
  if [ -n "$PROJECT_PATH" ] && [ "$PROJECT_PATH" != "." ]; then
    # Execute in the project directory
    (cd "$PROJECT_PATH" && eval "$PRE_COMMAND")
  else
    # Execute in the current directory
    eval "$PRE_COMMAND"
  fi
fi

# Run release script
if [ -f "/release.sh" ]; then
  echo "Running release process..."
  source /release.sh "$@"
else
  echo "Error: release.sh not found!"
  exit 1
fi

