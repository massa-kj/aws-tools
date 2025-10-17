#!/usr/bin/env bash
#=============================================================
# api.sh - AWS authentication API wrappers
#=============================================================

set -euo pipefail

# Load dependencies (explicit loading for clarity and testability)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

#--- SSO Authentication Methods --------------------------------

login_sso() {
  local profile="$1"
  log_info "Using SSO login for profile: ${profile}"
  aws sso login --profile "${profile}"
}

login_assume() {
  local profile="$1"
  local role_arn
  role_arn=$(aws configure get role_arn --profile "${profile}")
  local creds
  creds=$(aws sts assume-role --role-arn "${role_arn}" --role-session-name "auth-session")

  AWS_ACCESS_KEY_ID=$(jq -r '.Credentials.AccessKeyId' <<<"${creds}")
  export AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY=$(jq -r '.Credentials.SecretAccessKey' <<<"${creds}")
  export AWS_SECRET_ACCESS_KEY
  AWS_SESSION_TOKEN=$(jq -r '.Credentials.SessionToken' <<<"${creds}")
  export AWS_SESSION_TOKEN
}

login_access() {
  local profile="$1"
  log_info "Using static access key for profile: ${profile}"
  export AWS_PROFILE="${profile}"
}

#
# Check SSO session status
#
auth_sso_status() {
  local profile_name="${1:-}"
  
  if [[ -z "${profile_name}" ]]; then
    log_error "Usage: auth_sso_status <profile-name>"
    return 1
  fi
  
  if ! is_sso_profile "${profile_name}"; then
    log_error "Profile '${profile_name}' is not configured for SSO"
    return 1
  fi
  
  # Try to get caller identity with the SSO profile
  if aws sts get-caller-identity --profile "${profile_name}" >/dev/null 2>&1; then
    echo "active"
    return 0
  else
    echo "expired"
    return 1
  fi
}

#
# List available profiles
#
auth_list_profiles() {
  log_debug "Listing available AWS profiles"
  
  local profiles
  if ! profiles=$(aws configure list-profiles 2>/dev/null); then
    log_error "Failed to list profiles"
    return 1
  fi
  
  if [[ -z "${profiles}" ]]; then
    log_warn "No AWS profiles configured"
    return 0
  fi
  
  echo "Available AWS Profiles:"
  echo "======================="
  
  while IFS= read -r profile; do
    local profile_type="accesskey"
    local status_indicator=""
    
    # Determine profile type
    if is_sso_profile "${profile}"; then
      profile_type="sso"
      local sso_status
      auth_sso_status "${profile}" >/dev/null 2>&1
      local sso_result=$?
      if [[ ${sso_result} -eq 0 ]]; then
        sso_status="active"
      else
        sso_status="expired"
      fi
      if [[ "${sso_status}" == "active" ]]; then
        status_indicator=" ✓"
      else
        status_indicator=" (expired)"
      fi
    fi
    
    # Mark current profile
    local current_marker=""
    if [[ "${AWS_PROFILE:-}" == "${profile}" ]]; then
      current_marker=" *"
    fi
    
    printf "  %-20s [%-11s]%s%s\n" "${profile}" "${profile_type}" "${status_indicator}" "${current_marker}"
  done <<< "${profiles}"
  
  echo ""
  echo "Legend: * = current profile, ✓ = active SSO session"
}
