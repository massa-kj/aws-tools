#!/usr/bin/env bash
# ============================================================
# Logger
#
# Usage Example:
# ```sh
# # Load logger.sh from the same directory
# source "$(dirname "$0")/logger.sh"
# 
# # --- File output path (empty to disable file output) ---
# AWSTOOLS_LOG_FILE="./example.log"
# 
# # --- Basic output ---
# log_debug "This is debug info"
# log_info  "Starting process..."
# log_warn  "Low disk space"
# log_error "Connection failed"
# 
# # --- Color override output ---
# log_info --color="$COLOR_GREEN"  "✔ All checks passed"
# log_info --color="$COLOR_MAGENTA" "Processing data..."
# log_info --color="$COLOR_CYAN"   "Completed successfully"
# ```
# ============================================================

# ======= Configuration ======================================
AWSTOOLS_LOG_LEVEL="${AWSTOOLS_LOG_LEVEL:-INFO}"             # Output level
AWSTOOLS_LOG_FILE="${AWSTOOLS_LOG_FILE:-}"                   # File output path (empty to disable)
AWSTOOLS_LOG_USE_STDERR="${AWSTOOLS_LOG_USE_STDERR:-true}"   # Whether to use stderr
AWSTOOLS_LOG_USE_STDOUT="${AWSTOOLS_LOG_USE_STDOUT:-false}"  # Whether to use stdout (false for silent)
AWSTOOLS_LOG_USE_COLOR="${AWSTOOLS_LOG_USE_COLOR:-true}"     # Whether to use colors

# ======= Color definitions ==================================
COLOR_RESET="\033[0m"
COLOR_RED="\033[1;31m"
COLOR_YELLOW="\033[1;33m"
COLOR_GREEN="\033[1;32m"
COLOR_BLUE="\033[1;34m"
COLOR_MAGENTA="\033[1;35m"
COLOR_CYAN="\033[1;36m"
COLOR_GRAY="\033[0;90m"

# ======= Default colors by level ============================
declare -A LEVEL_COLORS=(
  [DEBUG]="$COLOR_GRAY"
  [INFO]="$COLOR_BLUE"
  [WARN]="$COLOR_YELLOW"
  [ERROR]="$COLOR_RED"
)

# ======= Log level priorities ===============================
declare -A LOG_LEVELS=(
  [DEBUG]=1
  [INFO]=2
  [WARN]=3
  [ERROR]=4
)

# ======= Log functions ======================================
log() {
  local level="$1"; shift
  local override_color=""
  local msg=""

  # Parse options: --color=<ANSI>
  if [[ "$1" =~ ^--color= ]]; then
    override_color="${1#--color=}"
    shift
  fi
  msg="$*"

  # Level filter (normalize to uppercase)
  local normalized_log_level="${AWSTOOLS_LOG_LEVEL^^}"
  if [[ ${LOG_LEVELS[$level]} -lt ${LOG_LEVELS[$normalized_log_level]} ]]; then
    return
  fi

  local ts caller color formatted output
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  caller="${BASH_SOURCE[2]##*/}:${BASH_LINENO[1]}"
  color=""
  [[ "$AWSTOOLS_LOG_USE_COLOR" == "true" ]] && color="${override_color:-${LEVEL_COLORS[$level]}}"

  formatted="[$ts][$level][$caller] $msg"
  output="${color}${formatted}${COLOR_RESET}"

  # File output
  if [[ -n "$AWSTOOLS_LOG_FILE" ]]; then
    printf "%s\n" "$formatted" >> "$AWSTOOLS_LOG_FILE"
  fi

  # Standard output/error output control
  if [[ "$AWSTOOLS_LOG_USE_STDERR" == "true" ]]; then
    printf "%b\n" "$output" >&2
  elif [[ "$AWSTOOLS_LOG_USE_STDOUT" == "true" ]]; then
    printf "%b\n" "$output"
  fi
}

# ======= Shortcut functions =================================
log_debug() { log DEBUG "$@"; }
log_info()  { log INFO  "$@"; }
log_warn()  { log WARN  "$@"; }
log_error() { log ERROR "$@"; }

# ======= Export functions ===================================
export -f log log_debug log_info log_warn log_error
