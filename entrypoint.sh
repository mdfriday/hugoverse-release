#!/bin/bash
set -e

# Display basic information
echo "Starting hugoverse build process..."
echo "Architecture: $(uname -m)"
echo "Host architecture: $(dpkg --print-architecture)"

# Run setup for Go
if [ -f "/setup-go.sh" ]; then
  echo "Setting up Go environment..."
  bash /setup-go.sh
else
  echo "Error: setup-go.sh not found!"
  exit 1
fi

# Run release script
if [ -f "/release.sh" ]; then
  echo "Running release process..."
  bash /release.sh "$@"
else
  echo "Error: release.sh not found!"
  exit 1
fi

