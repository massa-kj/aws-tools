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

# Modern alternative using aws configure export-credentials
login_universal() {
  local profile="$1"
  
  if [[ -z "$profile" ]]; then
    log_error "Usage: login_universal <profile-name>"
    return 1
  fi
  
  log_info "Using universal login for profile: ${profile}"
  
  # Use the new credential loading function
  if auth_load_credentials "$profile"; then
    log_info "Universal login successful for profile: ${profile}"
    return 0
  else
    log_error "Universal login failed for profile: ${profile}"
    return 1
  fi
}

login_access() {
  local profile="$1"
  log_info "Using static access key for profile: ${profile}"
  export AWS_PROFILE="${profile}"
}

#--- Credential Export Methods ---------------------------------

#
# Export AWS credentials as environment variables using aws configure export-credentials
# This is a more universal approach that works with SSO, assume role, and static credentials
#
auth_export_credentials() {
  local profile_name="${1:-}"
  local format="${2:-env}"
  local output_file="${3:-}"

  if [[ -z "$profile_name" ]]; then
    log_error "Usage: auth_export_credentials <profile-name> [format] [output-file]"
    log_error "Formats: env (default), json, shell"
    return 1
  fi

  if ! profile_exists "$profile_name"; then
    log_error "Profile '$profile_name' does not exist"
    return 1
  fi

  log_info "Exporting credentials for profile: $profile_name"
  log_debug "Format: $format"

  local aws_args=("configure" "export-credentials" "--profile" "$profile_name")

  case "$format" in
    env|shell)
      aws_args+=("--format" "env")
      ;;
    json)
      aws_args+=("--format" "json")
      ;;
    *)
      log_error "Unsupported format: $format. Use 'env', 'json', or 'shell'"
      return 1
      ;;
  esac

  local credentials_output
  if ! credentials_output=$(aws "${aws_args[@]}" 2>/dev/null); then
    log_error "Failed to export credentials for profile: $profile_name"
    log_error "Make sure the profile is properly configured and authenticated"
    return 1
  fi

  if [[ -n "$output_file" ]]; then
    echo "$credentials_output" > "$output_file"
    log_info "Credentials exported to: $output_file"
  else
    echo "$credentials_output"
  fi

  return 0
}

#
# Set environment variables from exported credentials
# This function combines export-credentials with environment variable setting
#
auth_load_credentials() {
  local profile_name="${1:-}"
  local temp_file

  if [[ -z "$profile_name" ]]; then
    log_error "Usage: auth_load_credentials <profile-name>"
    return 1
  fi

  if ! profile_exists "$profile_name"; then
    log_error "Profile '$profile_name' does not exist"
    return 1
  fi

  log_info "Loading credentials for profile: $profile_name"

  # Create temporary file for credentials
  temp_file=$(mktemp)
  
  # Export credentials to temporary file
  if ! auth_export_credentials "$profile_name" "env" "$temp_file"; then
    rm -f "$temp_file"
    return 1
  fi

  # Source the credentials file to set environment variables
  if source "$temp_file"; then
    log_info "Credentials loaded successfully for profile: $profile_name"
    
    # Clean up temporary file
    rm -f "$temp_file"
    
    # Validate the loaded credentials
    if validate_auth; then
      log_info "Credential validation successful"
      return 0
    else
      log_error "Credential validation failed"
      return 1
    fi
  else
    log_error "Failed to load credentials from exported file"
    rm -f "$temp_file"
    return 1
  fi
}

#
# Generate shell script with AWS credentials for sourcing
#
auth_generate_env_script() {
  local profile_name="${1:-}"
  local script_file="${2:-aws-credentials.sh}"

  if [[ -z "$profile_name" ]]; then
    log_error "Usage: auth_generate_env_script <profile-name> [script-file]"
    return 1
  fi

  log_info "Generating environment script for profile: $profile_name"

  cat > "$script_file" << EOF
#!/usr/bin/env bash
# AWS Credentials for profile: $profile_name
# Generated on: $(date)
# Usage: source $script_file

EOF

  if auth_export_credentials "$profile_name" "env" >> "$script_file"; then
    echo "" >> "$script_file"
    echo "echo \"AWS credentials loaded for profile: $profile_name\"" >> "$script_file"
    log_info "Environment script generated: $script_file"
    log_info "Usage: source $script_file"
    return 0
  else
    log_error "Failed to generate environment script"
    rm -f "$script_file"
    return 1
  fi
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
