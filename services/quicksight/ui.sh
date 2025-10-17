#!/usr/bin/env bash
#=============================================================
# ui.sh - User Interface 
#=============================================================

set -euo pipefail

# Load service-specific libraries (dependencies managed by lib.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"  # This also loads common libraries
source "${SCRIPT_DIR}/api.sh"

load_config "" "quicksight"

#--- Command Help Display ------------------------------------
show_help() {
  cat <<EOF
QuickSight Service Commands

Usage:
  awstools quicksight <command> [options...]

Available commands:
  list-datasets           List QuickSight datasets
  list-analyses           List QuickSight analyses
  export-datasets         Export QuickSight datasets definition
  export-analyses         Export QuickSight analyses definition
  export-all              Export QuickSight datasets & analyses definition
  help                    Show this help

Options:
  --profile <name>        Override AWS profile
  --region <region>       Override AWS region

Examples:
  awstools quicksight list-analyses
EOF
}

#--- Option Parsing ------------------------------------------
parse_options() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)
        export AWS_PROFILE="${2:-$AWS_PROFILE}"
        log_debug "Profile overridden to: ${AWS_PROFILE}"
        shift 2
        ;;
      --region)
        export AWS_REGION="${2:-$AWS_REGION}"
        log_debug "Region overridden to: ${AWS_REGION}"
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
cmd_list_target_analyses() {
  log_info "=== Target Analyses List ==="

  local all_analyses
  if ! all_analyses=$(get_all_analyses); then
    exit 1
  fi

  if ! filter_target_analyses "$all_analyses"; then
    exit 1
  fi

  log_info "Target analyses count: ${#MATCHED_ANALYSES[@]}"
  echo

  for analysis_info in "${MATCHED_ANALYSES[@]}"; do
    IFS='|' read -r analysis_name analysis_id created_time updated_time status <<< "$analysis_info"
    
    echo "Name: $analysis_name"
    echo "ID: $analysis_id"
    echo "Status: $status"
    echo "Created: $created_time"
    echo "Updated: $updated_time"
    echo "---"
  done
}

cmd_list_target_datasets() {
  log_info "=== Target Datasets List ==="

  local all_datasets
  if ! all_datasets=$(get_all_datasets); then
    exit 1
  fi
  
  if ! filter_target_datasets "$all_datasets"; then
    exit 1
  fi

  log_info "Target datasets count: ${#MATCHED_DATASETS[@]}"
  echo

  for dataset_info in "${MATCHED_DATASETS[@]}"; do
    IFS='|' read -r dataset_name dataset_id created_time updated_time import_mode <<< "$dataset_info"

    echo "Name: $dataset_name"
    echo "ID: $dataset_id"
    echo "Import mode: $import_mode"
    echo "Created: $created_time"
    echo "Updated: $updated_time"
    echo "---"
  done
}

cmd_export_analyses() {
  log_info "=== QuickSight Analysis Export ==="

  log_info "1. Retrieving all analyses list..."
  local all_analyses
  if ! all_analyses=$(get_all_analyses); then
    exit 1
  fi
  
  local analysis_count
  analysis_count=$(echo "$all_analyses" | jq -r '.AnalysisSummaryList | length')
  log_info "Retrieved analyses count: $analysis_count"

  log_info "2. Filtering target analyses..."
  if ! filter_target_analyses "$all_analyses"; then
    exit 1
  fi

  log_info "Target analyses count: ${#MATCHED_ANALYSES[@]}"
  
  # Create export directory
  local export_dir
  export_dir=$(generate_export_dir_name "analysis")
  mkdir -p "$export_dir"
  log_info "3. Created export directory: $export_dir"

  # Export analyses
  log_info "4. Exporting analyses..."
  if export_analyses "$export_dir"; then
    log_info "\n=== Export Completed ==="
    log_info "Export location: $export_dir"
  else
    log_error "\n=== Export Failed ==="
    exit 1
  fi
}

cmd_export_datasets() {
  log_info "=== QuickSight Dataset Export ==="

  log_info "1. Retrieving all datasets list..."
  local all_datasets
  if ! all_datasets=$(get_all_datasets); then
    exit 1
  fi

  local dataset_count
  dataset_count=$(echo "$all_datasets" | jq -r '.DataSetSummaries | length')
  log_info "Retrieved datasets count: $dataset_count"

  log_info "2. Filtering target datasets..."
  if ! filter_target_datasets "$all_datasets"; then
    exit 1
  fi

  log_info "Target datasets count: ${#MATCHED_DATASETS[@]}"

  # Create export directory
  local export_dir
  export_dir=$(generate_export_dir_name "dataset")
  mkdir -p "$export_dir"
  log_info "3. Created export directory: $export_dir"

  # Export datasets
  log_info "4. Exporting datasets..."
  if export_datasets "$export_dir"; then
    log_info "\n=== Export Completed ==="
    log_info "Export location: $export_dir"
  else
    log_error "\n=== Export Failed ==="
    exit 1
  fi
}

cmd_export_all() {
  local base_export_dir
  base_export_dir="quicksight-full-export-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$base_export_dir"

  log_info "=== QuickSight Full Export ==="
  log_info "Export directory: $base_export_dir"

  local error_count=0

  # Export analyses
  log_info "\n=== Analyses Export ==="
  local all_analyses
  if all_analyses=$(get_all_analyses) && filter_target_analyses "$all_analyses"; then
    local analysis_export_dir="$base_export_dir/analyses"
    mkdir -p "$analysis_export_dir"
    if ! export_analyses "$analysis_export_dir"; then
      ((error_count++))
    fi
  else
    ((error_count++))
  fi

  # Export datasets
  log_info "\n=== Datasets Export ==="
  local all_datasets
  if all_datasets=$(get_all_datasets) && filter_target_datasets "$all_datasets"; then
    local dataset_export_dir="$base_export_dir/datasets"
    mkdir -p "$dataset_export_dir"
    if ! export_datasets "$dataset_export_dir"; then
      ((error_count++))
    fi
  else
      ((error_count++))
  fi

  if [ $error_count -eq 0 ]; then
    log_info "\n=== Full Export Completed ==="
    log_info "Export location: $base_export_dir"
  else
    log_error "\n=== Export Failed ==="
    exit 1
  fi
}

#--- Main Processing -----------------------------------------

# Parse options
REMAINING_ARGS=()
parse_options "$@"
set -- "${REMAINING_ARGS[@]}"

# Get command
COMMAND="${1:-}"
if [[ -z "${COMMAND}" ]]; then
  show_help
  exit 1
fi
shift || true

# Execute command
case "$COMMAND" in
  list-datasets)
    cmd_list_target_datasets "$@"
    ;;
  list-analyses)
    cmd_list_target_analyses "$@"
    ;;
  export-datasets)
    cmd_export_datasets "$@"
    ;;
  export-analyses)
    cmd_export_analyses "$@"
    ;;
  export-all)
    cmd_export_all "$@"
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    log_error "Unknown command: $COMMAND"
    log_info "Run 'awstools quicksight help' for available commands"
    exit 1
    ;;
esac
