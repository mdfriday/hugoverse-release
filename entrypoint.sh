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
  
  # Handle binary name
  if [ -n "$INPUT_BINARY_NAME" ]; then
    export BINARY_NAME="$INPUT_BINARY_NAME"
    echo "Setting BINARY_NAME=$BINARY_NAME"
  fi
  
  echo "Environment setup complete"
fi

# Set default values for required variables
export PROJECT_PATH=${PROJECT_PATH:-.}
export BINARY_NAME=${BINARY_NAME:-hugoverse}

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

# Process project path: normalize and prepare directories
# Resolve paths before attempting to cd to them
normalize_path() {
  local path=$1
  local base_dir=${2:-$PWD}
  
  # Check if the path is absolute
  if [[ "$path" = /* ]]; then
    echo "$path"
    return
  fi
  
  # Handle paths with '..' components by computing the real path
  # Use a subshell to not affect the current directory
  (
    cd "$base_dir" || return 1
    if [[ "$path" == *".."* ]]; then
      # For paths with '..' components, use realpath to resolve them
      # Create intermediate directories if they don't exist
      local dir_to_create=$(dirname "$path")
      mkdir -p "$dir_to_create" 2>/dev/null || true
      realpath -m "$path" 2>/dev/null || echo "$path"
    else
      # For regular paths, just return as is
      echo "$path"
    fi
  )
}

# Normalize the project path
NORMALIZED_PROJECT_PATH=$(normalize_path "$PROJECT_PATH")
echo "Normalized project path: $NORMALIZED_PROJECT_PATH"

# Create project directory if it doesn't exist
if [ ! -d "$NORMALIZED_PROJECT_PATH" ]; then
  echo "Creating project directory: $NORMALIZED_PROJECT_PATH"
  mkdir -p "$NORMALIZED_PROJECT_PATH"
fi

# Execute pre-command if provided
if [ -n "$PRE_COMMAND" ]; then
  echo "Executing pre-command: $PRE_COMMAND"
  
  # Determine the directory to execute in
  if [ -n "$NORMALIZED_PROJECT_PATH" ] && [ "$NORMALIZED_PROJECT_PATH" != "." ]; then
    # Make sure the directory exists before cd
    if [ ! -d "$NORMALIZED_PROJECT_PATH" ]; then
      echo "Creating directory before running pre-command: $NORMALIZED_PROJECT_PATH"
      mkdir -p "$NORMALIZED_PROJECT_PATH"
    fi
    
    # Execute in the project directory
    echo "Running pre-command in: $NORMALIZED_PROJECT_PATH"
    (cd "$NORMALIZED_PROJECT_PATH" && eval "$PRE_COMMAND") || {
      echo "Error executing pre-command in $NORMALIZED_PROJECT_PATH"
      # Create parent directories and try again
      parent_dir=$(dirname "$NORMALIZED_PROJECT_PATH")
      echo "Trying to create parent directory: $parent_dir"
      mkdir -p "$parent_dir"
      (cd "$parent_dir" && eval "$PRE_COMMAND") || {
        echo "Error executing pre-command in parent directory. Running in current directory."
        eval "$PRE_COMMAND"
      }
    }
  else
    # Execute in the current directory
    eval "$PRE_COMMAND"
  fi
fi

# Export the normalized project path for release.sh
export PROJECT_PATH="$NORMALIZED_PROJECT_PATH"

# Run release script
if [ -f "/release.sh" ]; then
  echo "Running release process..."
  source /release.sh "$@"
else
  echo "Error: release.sh not found!"
  exit 1
fi

