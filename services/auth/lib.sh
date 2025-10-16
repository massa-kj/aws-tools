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


#
# Detect current authentication method
#
detect_auth_method() {
  # Check environment variables first
  if [[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    if [[ -n "${AWS_SESSION_TOKEN:-}" ]]; then
      echo "env-vars-session"
    else
      echo "env-vars"
    fi
    return 0
  fi
  
  # Check AWS_PROFILE
  if [[ -n "${AWS_PROFILE:-}" ]]; then
    if aws configure get sso_start_url --profile "${AWS_PROFILE}" >/dev/null 2>&1; then
      echo "profile-sso:${AWS_PROFILE}"
    elif aws configure get role_arn --profile "${AWS_PROFILE}" >/dev/null 2>&1; then
      echo "profile-assume:${AWS_PROFILE}"
    else
      echo "profile-accesskey:${AWS_PROFILE}"
    fi
    return 0
  fi
  
  # Check instance metadata (EC2 instance profile)
  if curl -sf --max-time 2 http://169.254.169.254/latest/meta-data/iam/security-credentials/ >/dev/null 2>&1; then
    echo "instance-profile"
    return 0
  fi
  
  # Check for web identity token (EKS, etc.)
  if [[ -n "${AWS_WEB_IDENTITY_TOKEN_FILE:-}" && -n "${AWS_ROLE_ARN:-}" ]]; then
    echo "web-identity"
    return 0
  fi
  
  # Default profile fallback
  if aws configure list-profiles 2>/dev/null | grep -q "^default$"; then
    if aws configure get sso_start_url --profile default >/dev/null 2>&1; then
      echo "profile-sso:default"
    elif aws configure get role_arn --profile default >/dev/null 2>&1; then
      echo "profile-assume:default"
    else
      echo "profile-accesskey:default"
    fi
    return 0
  fi
  
  echo "unknown"
  return 1
}

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

#
# Check if profile exists
#
profile_exists() {
  local profile_name="$1"
  
  if [[ -z "$profile_name" ]]; then
    log_error "Profile name is required"
    return 1
  fi
  
  aws configure list-profiles 2>/dev/null | grep "^${profile_name}$"
}

#
# Check if profile is SSO-based
#
is_sso_profile() {
  local profile_name="$1"
  
  if [[ -z "$profile_name" ]]; then
    log_error "Profile name is required"
    return 1
  fi
  
  aws configure get sso_account_id --profile "$profile_name" >/dev/null 2>&1
}

#
# Get profile configuration
#
get_profile_config() {
  local profile_name="$1"
  
  if [[ -z "$profile_name" ]]; then
    log_error "Profile name is required"
    return 1
  fi
  
  if ! profile_exists "$profile_name"; then
    log_error "Profile '$profile_name' does not exist"
    return 1
  fi
  
  local config_output
  config_output=$(aws configure list --profile "$profile_name" 2>/dev/null)
  
  echo "Profile Configuration: $profile_name"
  echo "$config_output"
  
  # Additional SSO/Role information
  if is_sso_profile "$profile_name"; then
    echo ""
    echo "SSO Configuration:"
    echo "  Start URL: $(aws configure get sso_start_url --profile "$profile_name" 2>/dev/null || echo "Not configured")"
    echo "  Account ID: $(aws configure get sso_account_id --profile "$profile_name" 2>/dev/null || echo "Not configured")"
    echo "  Role Name: $(aws configure get sso_role_name --profile "$profile_name" 2>/dev/null || echo "Not configured")"
  fi
}
