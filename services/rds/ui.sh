#!/usr/bin/env bash
#=============================================================
# ui.sh - User Interface for RDS service
#=============================================================

set -euo pipefail

# Load service-specific libraries (dependencies managed by lib.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"  # This also loads common libraries
source "$SCRIPT_DIR/api.sh"

load_config "" "rds"

#--- Command Help Display ------------------------------------
show_help() {
  cat <<EOF
RDS Service Commands

Usage:
  awstools rds <command> [options...]

Available commands:
  list                               List RDS database instances
  start <db-instance-identifier>     Start an RDS database instance
  stop <db-instance-identifier>      Stop an RDS database instance
  describe <db-instance-identifier>  Show detailed database instance information
  help                               Show this help

Options:
  --profile <name>                   Override AWS profile
  --region <region>                  Override AWS region

Examples:
  awstools rds list
  awstools rds start my-database
  awstools rds stop my-database --profile myteam
  awstools rds describe my-database
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

cmd_list() {
  log_info "Listing RDS instances in region '${AWS_REGION}' (profile=${AWS_PROFILE})..."
  ensure_aws_ready
  rds_list_instances
}

cmd_start() {
  local db_instance_id="${1:-}"
  if [ -z "$db_instance_id" ]; then
    log_error "Usage: awstools rds start <db-instance-identifier>"
    return 1
  fi
  
  log_info "Starting RDS instance: ${db_instance_id}"
  ensure_aws_ready
  
  # Check current status
  local current_status
  current_status=$(rds_get_instance_status "$db_instance_id") || return 1
  
  if [ "$current_status" = "available" ]; then
    log_warn "DB instance $db_instance_id is already available"
    return 0
  elif [ "$current_status" != "stopped" ]; then
    log_error "Cannot start DB instance $db_instance_id from status: $current_status"
    return 1
  fi
  
  # Start the instance
  rds_start_instance "$db_instance_id" || return 1
  
  # Wait for it to be available
  log_info "Waiting for DB instance to be available (this may take several minutes)..."
  rds_wait_for_instance_status "$db_instance_id" "available" "${AWSTOOLS_RDS_START_WAIT_TIMEOUT}"
}

cmd_stop() {
  local db_instance_id="${1:-}"
  if [ -z "$db_instance_id" ]; then
    log_error "Usage: awstools rds stop <db-instance-identifier>"
    return 1
  fi

  ensure_aws_ready

  # Check current status
  local current_status
  current_status=$(rds_get_instance_status "$db_instance_id") || return 1
  
  if [ "$current_status" = "stopped" ]; then
    log_warn "DB instance $db_instance_id is already stopped"
    return 0
  elif [ "$current_status" != "available" ]; then
    log_error "Cannot stop DB instance $db_instance_id from status: $current_status"
    return 1
  fi

  # Confirmation
  if ! confirm_action "Are you sure you want to stop DB instance ${db_instance_id}?" "no"; then
    log_warn "Operation cancelled by user."
    return 0
  fi

  log_info "Stopping RDS instance: ${db_instance_id}"
  rds_stop_instance "$db_instance_id" || return 1
  
  # Wait for it to be stopped
  log_info "Waiting for DB instance to stop (this may take several minutes)..."
  rds_wait_for_instance_status "$db_instance_id" "stopped" "${AWSTOOLS_RDS_STOP_WAIT_TIMEOUT}"
}

cmd_describe() {
  local db_instance_id="${1:-}"
  if [ -z "$db_instance_id" ]; then
    log_error "Usage: awstools rds describe <db-instance-identifier>"
    return 1
  fi
  log_info "Describing RDS instance: ${db_instance_id}"
  ensure_aws_ready
  rds_describe_instance "$db_instance_id"
}

#--- Main Processing -----------------------------------------

# Parse options
REMAINING_ARGS=()
parse_options "$@"
set -- "${REMAINING_ARGS[@]}"

# Get command
COMMAND="${1:-}"
if [ -z "$COMMAND" ]; then
  show_help
  exit 1
fi
shift || true

# Execute command
case "$COMMAND" in
  list)
    cmd_list "$@"
    ;;
  start)
    cmd_start "$@"
    ;;
  stop)
    cmd_stop "$@"
    ;;
  describe)
    cmd_describe "$@"
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    log_error "Unknown command: $COMMAND"
    log_info "Run 'awstools rds help' for available commands"
    exit 1
    ;;
esac
