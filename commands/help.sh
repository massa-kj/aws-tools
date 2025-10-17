#!/usr/bin/env bash
#=============================================================
# help.sh - Display help information
#=============================================================

set -euo pipefail

#--- Base configuration --------------------------------------
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON_DIR="${BASE_DIR}/common"

source "${COMMON_DIR}/logger.sh"
source "${COMMON_DIR}/discovery.sh"

#--- Main help display function -----------------------------
show_help() {
  cat <<EOF
AWS Tools - Unified CLI for multiple AWS services

Usage:
  awstools.sh <command> [args...]
  awstools.sh <service> <command> [args...]

Global commands:
$(list_global_commands)

Available services:
$(discover_services)

Common options:
  --version, -v          Show version information
  --help, -h             Show help

Examples:
  awstools.sh help
  awstools.sh ec2 list
  awstools.sh quicksight backup --profile my-profile
EOF
}

#--- Execute help command -----------------------------------
show_help
