#!/usr/bin/env bash
#=============================================================
# lib.sh - Helper utilities for service
#=============================================================

set -euo pipefail

# Load common dependencies (idempotent loading)
if [[ -z "${EC2_LIB_LOADED:-}" ]]; then
  # Determine script directory and base directory
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  BASE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
  COMMON_DIR="${BASE_DIR}/common"

  # Load common configuration and utilities only once
  if [[ -z "${AWS_TOOLS_CONFIG_LOADED:-}" ]]; then
    source "${COMMON_DIR}/config-loader.sh"
    export AWS_TOOLS_CONFIG_LOADED=1
  fi

  if [[ -z "${AWS_TOOLS_LOGGER_LOADED:-}" ]]; then
    source "${COMMON_DIR}/logger.sh"
    export AWS_TOOLS_LOGGER_LOADED=1
  fi

  if [[ -z "${AWS_TOOLS_UTILS_LOADED:-}" ]]; then
    source "${COMMON_DIR}/utils.sh"
    export AWS_TOOLS_UTILS_LOADED=1
  fi

  # Mark EC2 lib as loaded to prevent double-loading
  export EC2_LIB_LOADED=1

  log_debug "EC2 lib.sh loaded (dependencies: config=${AWS_TOOLS_CONFIG_LOADED}, logger=${AWS_TOOLS_LOGGER_LOADED}, utils=${AWS_TOOLS_UTILS_LOADED})"
fi

#--- EC2-specific utility functions ----------------------------

# Validate EC2 instance ID format
validate_instance_id() {
  local instance_id="$1"
  if [[ ! "${instance_id}" =~ ^i-[0-9a-f]{8,17}$ ]]; then
    log_error "Invalid instance ID format: ${instance_id}"
    return 1
  fi
}
