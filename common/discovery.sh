#!/usr/bin/env bash
#=============================================================
# discovery.sh - Service and command discovery utilities
#=============================================================

# Get base directory
DISCOVERY_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISCOVERY_SERVICES_DIR="${DISCOVERY_BASE_DIR}/services"
DISCOVERY_COMMANDS_DIR="${DISCOVERY_BASE_DIR}/commands"

#--- Global Commands Management ------------------------------

# Define available global commands
declare -A GLOBAL_COMMANDS=(
  ["version"]="Show version information"
  ["help"]="Show help information"
  ["detect-auth"]="Detect authentication source (profile, env-vars, iam-role)"
  # Add more global commands here as needed
  # ["config"]="Manage global configuration"
)

# Function to list all available global commands
list_global_commands() {
  for cmd in "${!GLOBAL_COMMANDS[@]}"; do
    printf "  - %-20s %s\n" "$cmd" "${GLOBAL_COMMANDS[$cmd]}"
  done
}

# Function to check if a command is a global command
is_global_command() {
  local cmd="$1"
  [[ -n "${GLOBAL_COMMANDS[$cmd]:-}" ]]
}

# Function to get command description
get_command_description() {
  local cmd="$1"
  echo "${GLOBAL_COMMANDS[$cmd]:-}"
}

#--- Service Discovery ---------------------------------------

# Discover available services dynamically
discover_services() {
  for dir in "${DISCOVERY_SERVICES_DIR}"/*/; do
    [[ -d "$dir" ]] || continue
    if [ -f "${dir}/manifest.sh" ]; then
      source "${dir}/manifest.sh"
      printf "  - %-20s %s (v%s)\n" "$SERVICE_NAME" "$SERVICE_DESC" "$SERVICE_VERSION"
    fi
  done
}

# Get list of available service names
get_service_names() {
  for dir in "${DISCOVERY_SERVICES_DIR}"/*/; do
    [[ -d "$dir" ]] || continue
    if [ -f "${dir}/manifest.sh" ]; then
      basename "$dir"
    fi
  done
}

# Check if a service exists
service_exists() {
  local service="$1"
  [[ -d "${DISCOVERY_SERVICES_DIR}/${service}" && -f "${DISCOVERY_SERVICES_DIR}/${service}/manifest.sh" ]]
}

# Get service information
get_service_info() {
  local service="$1"
  local manifest_file="${DISCOVERY_SERVICES_DIR}/${service}/manifest.sh"
  
  if [[ -f "$manifest_file" ]]; then
    source "$manifest_file"
    echo "Name: $SERVICE_NAME"
    echo "Description: $SERVICE_DESC"
    echo "Version: $SERVICE_VERSION"
  else
    echo "Service manifest not found: $service"
    return 1
  fi
}
