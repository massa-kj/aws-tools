#!/usr/bin/env bash
#=============================================================
# awstools.sh - Common entry point for tools
#
# Usage:
#   ./awstools.sh <service> <command> [options...]
#
# Example:
#   ./awstools.sh ec2 list
#   ./awstools.sh quicksight export --analysis-id abc123
#=============================================================

set -euo pipefail

#--- Base configuration --------------------------------------
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${BASE_DIR}/common"
SERVICES_DIR="${BASE_DIR}/services"
COMMANDS_DIR="${BASE_DIR}/commands"
source "${COMMON_DIR}/logger.sh"
#--- Help display --------------------------------------------
show_help() {
  cat <<EOF
AWS Tools - Unified CLI for multiple AWS services

Usage:
  $(basename "$0") <command> [args...]
  $(basename "$0") <service> <command> [args...]

Global commands:
$(list_global_commands)

Available services:
$(discover_services)

Common options:
  --help, -h             Show help
  --debug                Enable debug logging (LOG_LEVEL=debug)
  --no-color             Disable color output (LOG_COLOR=false)
  --log-file <path>      Output logs to specified file

Examples:
  $(basename "$0") detect-auth
  $(basename "$0") ec2 list
  $(basename "$0") quicksight backup --profile my-profile
EOF
}

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
while [[ $# -gt 0 ]]; do
  case "$1" in
    help|--help|-h)
      show_help; exit 0 ;;
    --version|-v)
      execute_global_command "version" "$@"; exit 0 ;;
    --debug)
      export LOG_LEVEL="debug"; shift ;;
    --no-color)
      export LOG_COLOR="false"; shift ;;
    --log-file)
      export LOG_FILE="$2"; shift 2 ;;
    *)
      # Check if it's a global command
      if is_global_command "$1"; then
        execute_global_command "$@"
      fi
      break ;;
  esac
done

#--- Argument check -----------------------------------------
if [ $# -lt 1 ]; then
  show_help; exit 1
fi

SERVICE="$1"; shift || true
SERVICE_DIR="${SERVICES_DIR}/${SERVICE}"

if [ ! -d "$SERVICE_DIR" ]; then
  log_error "Unknown command or service: ${SERVICE}"
  show_help
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
