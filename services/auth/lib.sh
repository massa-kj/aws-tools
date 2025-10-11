#!/usr/bin/env bash
#=============================================================
# lib.sh - Authentication utilities and configuration
#=============================================================

set -euo pipefail

# Load common dependencies (idempotent loading)
if [[ -z "${AUTH_LIB_LOADED:-}" ]]; then
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

  # Mark Auth lib as loaded to prevent double-loading
  export AUTH_LIB_LOADED=1

  log_debug "Auth lib.sh loaded (dependencies: config=${AWS_TOOLS_CONFIG_LOADED}, logger=${AWS_TOOLS_LOGGER_LOADED}, utils=${AWS_TOOLS_UTILS_LOADED})"
fi

#--- Authentication Helper Functions ------------------------

detect_auth_mode() {
  local profile="$1"

  # Whether SSO setting exists
  if aws configure get sso_start_url --profile "$profile" >/dev/null 2>&1; then
    echo "sso"
    return
  fi

  # Whether AssumeRole setting exists
  if aws configure get role_arn --profile "$profile" >/dev/null 2>&1; then
    echo "assume"
    return
  fi

  # Whether Access Key setting exists
  if aws configure get aws_access_key_id --profile "$profile" >/dev/null 2>&1; then
    echo "access"
    return
  fi

  echo "unknown"
}
