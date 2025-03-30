#!/bin/bash
set -e

# Display basic information
echo "Starting hugoverse build process..."
echo "Architecture: $(uname -m)"
echo "Host architecture: $(dpkg --print-architecture)"

# Convert GitHub Actions input variables to environment variables
if [ -n "$INPUT_GITHUB_TOKEN" ]; then
  echo "GitHub Actions detected, setting up environment variables..."
  export GITHUB_TOKEN="$INPUT_GITHUB_TOKEN"
  # Other potential Action inputs
  if [ -n "$INPUT_GOOS" ]; then
    export GOOS="$INPUT_GOOS"
  fi
  if [ -n "$INPUT_GOARCH" ]; then
    export GOARCH="$INPUT_GOARCH"
  fi
  if [ -n "$INPUT_EXTRA_FILES" ]; then
    export EXTRA_FILES="$INPUT_EXTRA_FILES"
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

# Run release script
if [ -f "/release.sh" ]; then
  echo "Running release process..."
  source /release.sh "$@"
else
  echo "Error: release.sh not found!"
  exit 1
fi

