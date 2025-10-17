#!/usr/bin/env bash
#=============================================================
# ui.sh - User Interface
#=============================================================

set -euo pipefail

# Load service-specific libraries (dependencies managed by lib.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"  # This also loads common libraries
source "${SCRIPT_DIR}/api.sh"

load_config "" "ec2"

#--- Command Help Display ------------------------------------
show_help() {
  cat <<EOF
EC2 Service Commands

Usage:
  awstools ec2 <command> [options...]

Available commands:
  list                    List EC2 instances
  start <instance-id>     Start an EC2 instance
  stop <instance-id>      Stop an EC2 instance
  describe <instance-id>  Show detailed instance information
  help                    Show this help

Options:
  --profile <name>        Override AWS profile
  --region <region>       Override AWS region

Examples:
  awstools ec2 list
  awstools ec2 start i-1234567890abcdef0
  awstools ec2 stop i-1234567890abcdef0 --profile myteam
EOF
}

#--- Option Parsing ------------------------------------------
parse_options() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)
        export AWS_PROFILE="${2:-${AWS_PROFILE}}"
        log_debug "Profile overridden to: ${AWS_PROFILE}"
        shift 2
        ;;
      --region)
        export AWS_REGION="${2:-${AWS_REGION}}"
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
  log_info "Listing EC2 instances in region '${AWS_REGION}' (profile=${AWS_PROFILE})..."
  ensure_aws_ready
  ec2_list_instances
}

cmd_start() {
  local instance_id="${1:-}"
  if [[ -z "${instance_id}" ]]; then
    log_error "Usage: awstools ec2 start <instance-id>"
    return 1
  fi

  log_info "Starting EC2 instance: ${instance_id}"
  ensure_aws_ready

  # Check current state
  local current_state
  current_state=$(ec2_get_instance_state "${instance_id}") || return 1

  if [[ "${current_state}" = "running" ]]; then
    log_warn "Instance ${instance_id} is already running"
    return 0
  elif [[ "${current_state}" != "stopped" ]]; then
    log_error "Cannot start instance ${instance_id} from state: ${current_state}"
    return 1
  fi

  # Start the instance
  ec2_start_instance "${instance_id}" || return 1

  # Wait for it to be running
  log_info "Waiting for instance to start..."
  ec2_wait_for_instance_state "${instance_id}" "running" 180
}

cmd_stop() {
  local instance_id="${1:-}"
  if [[ -z "${instance_id}" ]]; then
    log_error "Usage: awstools ec2 stop <instance-id>"
    return 1
  fi

  ensure_aws_ready

  # Check current state
  local current_state
  current_state=$(ec2_get_instance_state "${instance_id}") || return 1

  if [[ "${current_state}" = "stopped" ]]; then
    log_warn "Instance ${instance_id} is already stopped"
    return 0
  elif [[ "${current_state}" != "running" ]]; then
    log_error "Cannot stop instance ${instance_id} from state: ${current_state}"
    return 1
  fi

  # Confirmation
  if ! confirm_action "Are you sure you want to stop instance ${instance_id}?" "no"; then
    log_warn "Operation cancelled by user."
    return 0
  fi

  log_info "Stopping EC2 instance: ${instance_id}"
  ec2_stop_instance "${instance_id}" || return 1

  # Wait for it to be stopped
  log_info "Waiting for instance to stop..."
  ec2_wait_for_instance_state "${instance_id}" "stopped" 180
}

cmd_describe() {
  local instance_id="${1:-}"
  if [[ -z "${instance_id}" ]]; then
    log_error "Usage: awstools ec2 describe <instance-id>"
    return 1
  fi
  log_info "Describing EC2 instance: ${instance_id}"
  ensure_aws_ready
  ec2_describe_instance "${instance_id}"
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
case "${COMMAND}" in
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
    log_error "Unknown command: ${COMMAND}"
    log_info "Run 'awstools ec2 help' for available commands"
    exit 1
    ;;
esac
