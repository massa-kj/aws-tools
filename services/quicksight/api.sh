#!/usr/bin/env bash
#=============================================================
# api.sh - Low-level AWS CLI wrappers
#=============================================================

set -euo pipefail

# Load dependencies (explicit loading for clarity and testability)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

get_all_datasets() {
  local all_datasets
  all_datasets=$(aws_exec quicksight list-data-sets --aws-account-id "$ACCOUNT_ID" --output json 2>/dev/null)

  if [ $? -ne 0 ] || [ "$all_datasets" = "null" ]; then
    log_error "Error: Failed to retrieve datasets."
    return 1
  fi

  echo "$all_datasets"
}

get_all_analyses() {
  local all_analyses
  all_analyses=$(aws_exec quicksight list-analyses --aws-account-id "$ACCOUNT_ID" --output json 2>/dev/null)

  if [ $? -ne 0 ] || [ "$all_analyses" = "null" ]; then
    log_error "Error: Failed to retrieve analyses."
    return 1
  fi

  echo "$all_analyses"
}
