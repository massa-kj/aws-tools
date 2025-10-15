#!/usr/bin/env bash
#=============================================================
# lib.sh - Helper utilities for RDS service
#=============================================================

set -euo pipefail

# Load common dependencies (idempotent loading)
if [[ -z "${RDS_LIB_LOADED:-}" ]]; then
  # Determine script directory and base directory
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
  COMMON_DIR="$BASE_DIR/common"

  # Load common configuration and utilities only once
  if [[ -z "${AWS_TOOLS_CONFIG_LOADED:-}" ]]; then
    source "$COMMON_DIR/config-loader.sh"
    export AWS_TOOLS_CONFIG_LOADED=1
  fi

  if [[ -z "${AWS_TOOLS_LOGGER_LOADED:-}" ]]; then
    source "$COMMON_DIR/logger.sh"
    export AWS_TOOLS_LOGGER_LOADED=1
  fi

  if [[ -z "${AWS_TOOLS_UTILS_LOADED:-}" ]]; then
    source "$COMMON_DIR/utils.sh"
    export AWS_TOOLS_UTILS_LOADED=1
  fi

  # Mark RDS lib as loaded to prevent double-loading
  export RDS_LIB_LOADED=1

  log_debug "RDS lib.sh loaded (dependencies: config=${AWS_TOOLS_CONFIG_LOADED}, logger=${AWS_TOOLS_LOGGER_LOADED}, utils=${AWS_TOOLS_UTILS_LOADED})"
fi

#--- RDS-specific utility functions ----------------------------

# Validate RDS DB instance identifier format
validate_db_instance_id() {
  local db_instance_id="$1"
  # RDS DB instance identifiers must be:
  # - 1-63 characters long
  # - Contain only lowercase letters, numbers, and hyphens
  # - Begin with a letter
  # - End with an alphanumeric character
  if [[ ! "$db_instance_id" =~ ^[a-z][a-z0-9-]{0,61}[a-z0-9]$ ]]; then
    log_error "Invalid DB instance identifier format: $db_instance_id"
    log_error "Must be 1-63 characters, lowercase letters/numbers/hyphens, start with letter, end with alphanumeric"
    return 1
  fi
}

# Find available local port for SSH tunneling
find_available_port() {
  local start_port="${1:-5432}"
  local max_attempts=50
  local port=$start_port
  
  for ((i=0; i<max_attempts; i++)); do
    if ! command -v netstat >/dev/null 2>&1; then
      # If netstat is not available, try nc or ss
      if command -v nc >/dev/null 2>&1; then
        if ! nc -z localhost "$port" 2>/dev/null; then
          echo "$port"
          return 0
        fi
      elif command -v ss >/dev/null 2>&1; then
        if ! ss -ln | grep -q ":$port "; then
          echo "$port"
          return 0
        fi
      else
        # Fallback: just return the port (might fail later)
        echo "$port"
        return 0
      fi
    else
      if ! netstat -ln | grep -q ":$port "; then
        echo "$port"
        return 0
      fi
    fi
    port=$((port + 1))
  done
  
  log_error "Could not find available port after $max_attempts attempts"
  return 1
}

# Parse RDS connection string/endpoint
parse_rds_endpoint() {
  local endpoint="$1"
  local parsed_info
  
  # Extract hostname and port from endpoint
  if [[ "$endpoint" =~ ^(.+):([0-9]+)$ ]]; then
    parsed_info="{\"host\":\"${BASH_REMATCH[1]}\",\"port\":\"${BASH_REMATCH[2]}\"}"
  else
    # Assume default port based on engine type (will be handled by caller)
    parsed_info="{\"host\":\"$endpoint\",\"port\":\"\"}"
  fi
  
  echo "$parsed_info"
}


