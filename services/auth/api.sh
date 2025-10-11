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
  log_info "Using SSO login for profile: $profile"
  aws sso login --profile "$profile"
}

login_assume() {
  local profile="$1"
  local role_arn
  role_arn=$(aws configure get role_arn --profile "$profile")
  local creds
  creds=$(aws sts assume-role --role-arn "$role_arn" --role-session-name "auth-session")

  export AWS_ACCESS_KEY_ID=$(jq -r '.Credentials.AccessKeyId' <<<"$creds")
  export AWS_SECRET_ACCESS_KEY=$(jq -r '.Credentials.SecretAccessKey' <<<"$creds")
  export AWS_SESSION_TOKEN=$(jq -r '.Credentials.SessionToken' <<<"$creds")
}

login_access() {
  local profile="$1"
  log_info "Using static access key for profile: $profile"
  export AWS_PROFILE="$profile"
}
