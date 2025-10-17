#!/usr/bin/env bash
#=============================================================
# ui.sh - Authentication User Interface 
#=============================================================

set -euo pipefail

# Load service-specific libraries (dependencies managed by lib.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"  # This also loads common libraries
source "${SCRIPT_DIR}/api.sh"

load_config "" "auth"

#--- Command Help Display ------------------------------------
show_help() {
  cat <<EOF
Authentication Service Commands

Usage:
  awstools auth <command> [options...]

Available commands:
  detect                  Detect authentication method
  sso-login <profile>     Login using AWS SSO
  list-profiles           List available profiles
  profile-info <profile>  Show detailed profile configuration
  help                    Show this help

Options:
  --region <region>       Override AWS region

Examples:
  awstools auth detect
  awstools auth sso-login my-sso-profile
  awstools auth list-profiles
  awstools auth profile-info my-profile
EOF
}

#--- Option Parsing ------------------------------------------
parse_options() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --region)
        OVERRIDE_REGION="${2:-}"
        if [[ -n "${OVERRIDE_REGION}" ]]; then
          export AWS_REGION="${OVERRIDE_REGION}"
          log_debug "Region overridden to: ${AWS_REGION}"
        fi
        shift 2
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        # Keep remaining arguments
        REMAINING_ARGS+=("$1")
        shift
        ;;
    esac
  done
}

#--- Command Implementation -----------------------------------

cmd_sso_login() {
  local profile_name="${1:-${AWS_PROFILE}}"
  
  if [[ -z "${profile_name}" ]]; then
    log_error "Usage: awstools auth login-sso <profile-name>"
    return 1
  fi
  
  log_info "Logging in with SSO profile: ${profile_name}"

  if login_sso "${profile_name}"; then
    log_info "✅ SSO login successful"
    export AWS_PROFILE="${profile_name}"
  else
    log_error "❌ SSO login failed"
    return 1
  fi
}

cmd_detect() {
  log_debug "Detecting authentication method"
  
  local method
  method=$(detect_auth_method)
  
  echo "Detected authentication method: ${method}"
  
  case "${method}" in
    env-vars*)
      echo "Using environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)"
      ;;
    profile-sso:*)
      local profile_name="${method#*:}"
      echo "Using SSO profile: ${profile_name}"
      local sso_status
      sso_status=$(auth_sso_status "${profile_name}" 2>/dev/null || echo "expired")
      echo "SSO session status: ${sso_status}"
      ;;
    profile-assume:*)
      local profile_name="${method#*:}"
      echo "Using assume role profile: ${profile_name}"
      ;;
    profile-accesskey:*)
      local profile_name="${method#*:}"
      echo "Using access key profile: ${profile_name}"
      ;;
    instance-profile)
      echo "Using EC2 instance profile"
      ;;
    web-identity)
      echo "Using web identity token (EKS, etc.)"
      ;;
    unknown)
      echo "No authentication method detected"
      return 1
      ;;
    *)
      echo "Unexpected authentication method: ${method}"
      return 1
      ;;
  esac
}

cmd_list_profiles() {
  log_debug "Listing available profiles"
  auth_list_profiles
}

cmd_profile_info() {
  local profile_name="${1:-}"
  
  if [[ -z "${profile_name}" ]]; then
    log_error "Usage: awstools auth profile-info <profile-name>"
    return 1
  fi
  
  log_debug "Getting profile information for: ${profile_name}"
  get_profile_config "${profile_name}"
}

#--- Main Processing -----------------------------------------

# Initialize variables
REMAINING_ARGS=()
# Parse options
parse_options "$@"
set -- "${REMAINING_ARGS[@]}"

# Get command
COMMAND="${1:-}"
if [[ -z "${COMMAND}" ]]; then
  show_help
  exit 1
fi
shift || true

# Execute command
case "${COMMAND}" in
  detect)
    cmd_detect "$@"
    ;;
  sso-login)
    cmd_sso_login "$@"
    ;;
  list-profiles)
    cmd_list_profiles "$@"
    ;;
  profile-info)
    cmd_profile_info "$@"
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    log_error "Unknown command: ${COMMAND}"
    log_info "Run 'awstools auth help' for available commands"
    exit 1
    ;;
esac
