#!/usr/bin/env bash
#=============================================================
# version.sh - Show version information
#=============================================================

set -euo pipefail

# Load common utilities
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${BASE_DIR}/common/logger.sh"

show_version() {
  cat <<EOF
AWS Tools v1.0.0

For help and available commands:
  awstools help
  awstools <command> help
  awstools <service> help
EOF
}

# Show help if requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<EOF
version - Show version information

Usage:
  awstools version

Description:
  Displays version information.

Examples:
  awstools version
EOF
  exit 0
fi

show_version
