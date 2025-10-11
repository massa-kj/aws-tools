#!/usr/bin/env bash
#=============================================================
# ui.sh - Authentication User Interface 
#=============================================================

set -euo pipefail

# Load service-specific libraries (dependencies managed by lib.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"  # This also loads common libraries
source "$SCRIPT_DIR/api.sh"

load_config "" "auth"

#--- Command Help Display ------------------------------------
show_help() {
  cat <<EOF
Authentication Service Commands

Usage:
  awstools auth <command> [options...]

Available commands:
  sso-login <profile>     Login using AWS SSO
  help                    Show this help

Options:
  --region <region>       Override AWS region

Examples:
  awstools auth sso-login my-sso-profile
EOF
}

#--- Option Parsing ------------------------------------------
parse_options() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --region)
        OVERRIDE_REGION="${2:-}"
        if [[ -n "$OVERRIDE_REGION" ]]; then
          export AWS_REGION="$OVERRIDE_REGION"
          log_debug "Region overridden to: $AWS_REGION"
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
  local profile_name="${1:-}"
  
  if [[ -z "$profile_name" ]]; then
    log_error "Usage: awstools auth login-sso <profile-name>"
    return 1
  fi
  
  log_info "Logging in with SSO profile: $profile_name"

  if login_sso "$profile_name"; then
    log_info "✅ SSO login successful"
    export AWS_PROFILE="$profile_name"
  else
    log_error "❌ SSO login failed"
    return 1
  fi
}

#--- Main Processing -----------------------------------------

# Initialize variables
REMAINING_ARGS=()
# Parse options
parse_options "$@"
set -- "${REMAINING_ARGS[@]}"

# Get command
COMMAND="${1:-}"
if [ -z "$COMMAND" ]; then
  show_help
  exit 1
fi
shift || true

# Execute command
case "$COMMAND" in
  sso-login)
    cmd_sso_login "$@"
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    log_error "Unknown command: $COMMAND"
    log_info "Run 'awstools auth help' for available commands"
    exit 1
    ;;
esac
