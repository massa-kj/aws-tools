#!/usr/bin/env bash
#=============================================================
# init-user-config.sh - Initialize user configuration
#
# This script creates the user configuration directory and
# default configuration file for awstools.
#=============================================================

set -euo pipefail

#--- Base configuration --------------------------------------
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${BASE_DIR}/../common/logger.sh"

# Configuration
USER_CONFIG_DIR="${HOME}/.config/awstools"
USER_CONFIG_FILE="${USER_CONFIG_DIR}/config"

# Create user configuration directory
create_config_dir() {
  if [[ ! -d "$USER_CONFIG_DIR" ]]; then
    log_info "Creating user configuration directory: $USER_CONFIG_DIR"
    mkdir -p "$USER_CONFIG_DIR"
    log_info "Configuration directory created"
  else
    log_info "Configuration directory already exists: $USER_CONFIG_DIR"
  fi
}

# Create default configuration file
create_default_config() {
  if [[ -f "$USER_CONFIG_FILE" ]]; then
    log_warn "Configuration file already exists: $USER_CONFIG_FILE"
    read -p "Do you want to overwrite it? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log_info "Keeping existing configuration file"
      return 0
    fi
  fi

  log_info "Creating default configuration file: $USER_CONFIG_FILE"
  
  cat > "$USER_CONFIG_FILE" << 'EOF'
# AWS Tools Configuration File
# This file contains user-specific configuration for awstools

# Default profile to use when no profile is specified
# AWSTOOLS_PROFILE="dev"

# Directory containing profile-specific configurations
# Each profile should have its own subdirectory under this path
# Example: ~/.config/awstools/profiles/dev, ~/.config/awstools/profiles/prod
# AWSTOOLS_PROFILE_DIR="~/.config/awstools/profiles"

# Example profile directory structure:
# ~/.config/awstools/profiles/
# ├── dev/
# │   ├── common.env
# │   ├── services/
# │   │   ├── ec2.env
# │   │   └── rds.env
# │   └── any-custom.env
# └── prod/
#     ├── common.env
#     └── services/
#         └── ec2.env
#
# All .env files in the profile directory (and subdirectories) will be loaded recursively
EOF

  log_info "Default configuration file created"
  log_info "Please edit $USER_CONFIG_FILE to configure your profiles"
}

# Show usage information
show_usage() {
  cat << EOF

AWS Tools User Configuration Initialization
===========================================

This script initializes your user configuration for awstools.

Configuration will be created at:
  Directory: $USER_CONFIG_DIR
  File: $USER_CONFIG_FILE

After initialization, you can:
1. Edit the configuration file to set your default profile and profile directory
2. Create profile-specific directories with .env files
3. Use --profile option to override the default profile at runtime

Example usage:
  # Use default profile
  ./awstools.sh ec2 list-instances

  # Use specific profile
  ./awstools.sh --profile prod ec2 list-instances

EOF
}

# Main function
main() {
  case "${1:-}" in
    --help|-h)
      show_usage
      exit 0
      ;;
    *)
      log_info "Initializing AWS Tools user configuration..."
      create_config_dir
      create_default_config
      echo
      log_info "User configuration initialization completed!"
      log_info "Edit $USER_CONFIG_FILE to configure your profiles"
      ;;
  esac
}

main "$@"