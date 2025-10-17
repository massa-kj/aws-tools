#!/usr/bin/env bash
#=============================================================
# lint.sh - Shell script linting tool
#=============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load common logger
source "$BASE_DIR/common/logger.sh"

# Configuration
SHELLCHECK_ENABLED=true
QUIET_MODE=false

# Function to check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to show usage
show_usage() {
  cat <<EOF
Shell Script Linting Tool

Usage: $0 [OPTIONS] [FILES...]

OPTIONS:
  --quiet           Suppress output except for errors
  --no-shellcheck   Skip ShellCheck linting
  --help           Show this help message

EXAMPLES:
  $0                          # Lint all shell scripts in the project
  $0 awstools.sh             # Lint specific file

TOOLS USED:
  - ShellCheck: Static analysis for shell scripts
EOF
}

# Function to find shell scripts
find_shell_scripts() {
  local search_paths=("$@")

  if [ ${#search_paths[@]} -eq 0 ]; then
    search_paths=("$BASE_DIR")
  fi

  # Find shell scripts by extension and shebang
  for path in "${search_paths[@]}"; do
    if [ -f "$path" ]; then
      echo "$path"
    elif [ -d "$path" ]; then
      # Find by extension
      find "$path" -name "*.sh" -o -name "*.bash" 2>/dev/null || true

      # Find by shebang (excluding common directories to avoid)
      find "$path" -type f -not -path "*/\.*" -not -path "*/node_modules/*" \
        -not -path "*/vendor/*" -not -path "*/build/*" \
        -exec grep -l '^#!/.*\(bash\|sh\)' {} \; 2>/dev/null || true
    fi
  done | sort -u
}

# Function to run ShellCheck
run_shellcheck() {
  local files=("$@")
  local exit_code=0

  if [ "$SHELLCHECK_ENABLED" != "true" ]; then
    return 0
  fi

  if ! command_exists shellcheck; then
    log_error "ShellCheck not found."
    return 1
  fi

  log_info --color="$COLOR_BLUE" "Running ShellCheck..."

  for file in "${files[@]}"; do
    if [ "$QUIET_MODE" != "true" ]; then
      echo "Checking: $file"
    fi

    if ! shellcheck "$file"; then
      exit_code=1
    fi
  done

  return $exit_code
}

# Main function
main() {
  local search_paths=()

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --quiet)
        QUIET_MODE=true
        shift
        ;;
      --no-shellcheck)
        SHELLCHECK_ENABLED=false
        shift
        ;;
      --help|-h)
        show_usage
        exit 0
        ;;
      -*)
        log_error "Unknown option: $1"
        show_usage
        exit 1
        ;;
      *)
        search_paths+=("$1")
        shift
        ;;
    esac
  done

  # Find shell scripts
  mapfile -t shell_files < <(find_shell_scripts "${search_paths[@]}")

  if [ ${#shell_files[@]} -eq 0 ]; then
    log_warn "No shell scripts found."
    exit 0
  fi

  if [ "$QUIET_MODE" != "true" ]; then
    log_info --color="$COLOR_GREEN" "Found ${#shell_files[@]} shell script(s)"
  fi

  local overall_exit_code=0

  # Run ShellCheck
  if ! run_shellcheck "${shell_files[@]}"; then
    overall_exit_code=1
  fi

  # Summary
  if [ $overall_exit_code -eq 0 ]; then
    log_info --color="$COLOR_GREEN" "✓ All checks passed!"
  else
    log_error "✗ Some checks failed!"
  fi

  exit $overall_exit_code
}

# Run main function
main "$@"
