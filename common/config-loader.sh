#!/usr/bin/env bash
#=============================================================
# config-loader.sh - Load configuration for AWS tools
#=============================================================

# Get user config directory
get_user_config_dir() {
  echo "${HOME}/.config/awstools"
}

# Get user config file path
get_user_config_file() {
  echo "$(get_user_config_dir)/config"
}

# Load user configuration
load_user_config() {
  local config_file="$(get_user_config_file)"
  if [[ -f "$config_file" ]]; then
    # shellcheck disable=SC1090
    source "$config_file"
  fi
}

# Get effective profile
get_effective_profile() {
  # Command line override takes precedence
  if [[ -n "${AWSTOOLS_PROFILE_OVERRIDE:-}" ]]; then
    # Remove trailing slash if present
    echo "${AWSTOOLS_PROFILE_OVERRIDE%/}"
    return 0
  fi

  # Load user config to get default profile
  load_user_config

  # Use configured profile or fallback to "default", remove trailing slash
  local profile="${AWSTOOLS_PROFILE:-default}"
  echo "${profile%/}"
}

# Get profile directory path
get_profile_dir() {
  local profile="$1"
  load_user_config

  # Check if AWSTOOLS_PROFILE_DIR is set
  if [[ -n "${AWSTOOLS_PROFILE_DIR:-}" ]]; then
    # Expand tilde if present
    local expanded_dir="${AWSTOOLS_PROFILE_DIR/#~/$HOME}"
    # Remove trailing slash from profile name if present
    local clean_profile="${profile%/}"
    echo "${expanded_dir}/${clean_profile}"
  else
    # Fallback to repository config for backward compatibility
    echo ""
  fi
}

# Recursively load all .env files from a directory
load_env_files_recursive() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    return 0
  fi

  # Find all .env files and sort them for consistent loading order
  while IFS= read -r -d '' env_file; do
    if [[ -f "$env_file" ]]; then
      # shellcheck disable=SC1090
      source "$env_file"
    fi
  done < <(find "$dir" -name "*.env" -type f -print0 | sort -z)
}

validate_config() {
  return 0
}

show_effective_config() {
  return 0
}

load_config() {
  local environment="${1:-}"
  local service="${2:-}"
  local base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../config" && pwd)"

  # First, load default configurations as fallback
  load_env_files_recursive "${base_dir}/default"

  # Determine the effective profile
  local effective_profile
  if [[ -n "$environment" ]]; then
    effective_profile="$environment"
  else
    effective_profile="$(get_effective_profile)"
  fi

  # Load profile-specific configurations
  local profile_dir="$(get_profile_dir "$effective_profile")"
  if [[ -n "$profile_dir" && -d "$profile_dir" ]]; then
    load_env_files_recursive "$profile_dir"
  fi

  # Set the effective profile
  export AWSTOOLS_PROFILE="$effective_profile"

  return 0
}
