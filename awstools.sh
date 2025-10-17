#!/usr/bin/env bash
#=============================================================
# awstools.sh - Common entry point for tools
#
# Usage:
#   ./awstools.sh <service> <command> [options...]
#   ./awstools.sh <command> [options...]
#=============================================================

set -euo pipefail

#--- Base configuration --------------------------------------
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${BASE_DIR}/common"
SERVICES_DIR="${BASE_DIR}/services"
COMMANDS_DIR="${BASE_DIR}/commands"
source "${COMMON_DIR}/logger.sh"
source "${COMMON_DIR}/discovery.sh"

#--- Execute global command function ------------------------
execute_global_command() {
  local cmd="$1"
  shift || true

  local cmd_script="${COMMANDS_DIR}/${cmd}.sh"
  if [ ! -f "$cmd_script" ]; then
    log_error "Global command script not found: ${cmd_script}"
    exit 1
  fi

  log_debug "Executing global command: ${cmd}"
  exec "$cmd_script" "$@"
}

#--- Option parsing (pre-processing) -------------------------
# Initialize profile variable
AWSTOOLS_PROFILE_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version|-v)
      execute_global_command "version" "$@"; exit 0 ;;
    --help|-h)
      execute_global_command "help" "$@"; exit 0 ;;
    --profile)
      shift
      if [[ $# -eq 0 ]] || [[ "$1" == --* ]]; then
        log_error "Option --profile requires a value"
        exit 1
      fi
      AWSTOOLS_PROFILE_OVERRIDE="$1"
      shift
      ;;
    *)
      # Check if it's a global command
      if is_global_command "$1"; then
        execute_global_command "$@"
      fi
      break ;;
  esac
done

# Export profile override for child processes
if [[ -n "$AWSTOOLS_PROFILE_OVERRIDE" ]]; then
  export AWSTOOLS_PROFILE_OVERRIDE
fi

#--- Argument check -----------------------------------------
if [ $# -lt 1 ]; then
  execute_global_command "help"
  exit 1
fi

SERVICE="$1"; shift || true
SERVICE_DIR="${SERVICES_DIR}/${SERVICE}"

if [ ! -d "$SERVICE_DIR" ]; then
  log_error "Unknown command or service: ${SERVICE}"
  execute_global_command "help"
  exit 1
fi

#--- Delegate to service UI layer ----------------------------
UI_SCRIPT="${SERVICE_DIR}/ui.sh"
if [ ! -f "$UI_SCRIPT" ]; then
  log_error "Service UI not found: ${UI_SCRIPT}"
  exit 1
fi

# Delegate all sub-command processing to the service's ui.sh
log_debug "Delegating to service UI: ${UI_SCRIPT}"
exec "$UI_SCRIPT" "$@"
