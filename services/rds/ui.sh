#!/usr/bin/env bash
#=============================================================
# ui.sh - User Interface for RDS service
#=============================================================

set -euo pipefail

# Load service-specific libraries (dependencies managed by lib.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"  # This also loads common libraries
source "${SCRIPT_DIR}/api.sh"

load_config "" "rds"

#--- Command Help Display ------------------------------------
show_help() {
  cat <<EOF
RDS Service Commands

Usage:
  awstools rds <command> [options...]

Available commands:
  list                               List RDS database instances
  start [db-instance-identifier]     Start an RDS database instance
  stop [db-instance-identifier]      Stop an RDS database instance
  describe [db-instance-identifier]  Show detailed database instance information
  connect [db-instance-identifier]   Connect to RDS via Session Manager tunnel
  help                               Show this help

Options:
  common options:
  --profile <name>                   Override AWS profile
  --region <region>                  Override AWS region

  connect command options:
  --instance-id <id>                 Specify EC2 instance for tunneling
  --local-port <port>                Specify local port for tunneling

Examples:
  awstools rds list
  awstools rds start my-database
  awstools rds stop my-database --profile myteam
  awstools rds describe my-database
  awstools rds connect my-database
  awstools rds connect my-database --instance-id i-1234567890abcdef0 --local-port 15432
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
      --instance-id)
        BASTION_INSTANCE_ID="${2:-}"
        log_debug "Bastion instance ID: ${BASTION_INSTANCE_ID}"
        shift 2
        ;;
      --local-port)
        TUNNEL_LOCAL_PORT="${2:-}"
        log_debug "Local tunnel port: ${TUNNEL_LOCAL_PORT}"
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
  local db_instance_id="${1:-${AWSTOOLS_RDS_DEFAULT_INSTANCE_ID}}"
  if [[ -z "${db_instance_id}" ]]; then
    log_error "Usage: awstools rds start <db-instance-identifier>"
    return 1
  fi

  log_info "Starting RDS instance: ${db_instance_id}"
  ensure_aws_ready

  # Check current status
  local current_status
  current_status=$(rds_get_instance_status "${db_instance_id}") || return 1

  if [[ "${current_status}" = "available" ]]; then
    log_warn "DB instance ${db_instance_id} is already available"
    return 0
  elif [[ "${current_status}" != "stopped" ]]; then
    log_error "Cannot start DB instance ${db_instance_id} from status: ${current_status}"
    return 1
  fi

  # Start the instance
  rds_start_instance "${db_instance_id}" || return 1

  # Wait for it to be available
  log_info "Waiting for DB instance to be available (this may take several minutes)..."
  rds_wait_for_instance_status "${db_instance_id}" "available" "${AWSTOOLS_RDS_START_WAIT_TIMEOUT}"
}

cmd_stop() {
  local db_instance_id="${1:-${AWSTOOLS_RDS_DEFAULT_INSTANCE_ID}}"
  if [[ -z "${db_instance_id}" ]]; then
    log_error "Usage: awstools rds stop <db-instance-identifier>"
    return 1
  fi

  ensure_aws_ready

  # Check current status
  local current_status
  current_status=$(rds_get_instance_status "${db_instance_id}") || return 1

  if [[ "${current_status}" = "stopped" ]]; then
    log_warn "DB instance ${db_instance_id} is already stopped"
    return 0
  elif [[ "${current_status}" != "available" ]]; then
    log_error "Cannot stop DB instance ${db_instance_id} from status: ${current_status}"
    return 1
  fi

  # Confirmation
  if ! confirm_action "Are you sure you want to stop DB instance ${db_instance_id}?" "no"; then
    log_warn "Operation cancelled by user."
    return 0
  fi

  log_info "Stopping RDS instance: ${db_instance_id}"
  rds_stop_instance "${db_instance_id}" || return 1

  # Wait for it to be stopped
  log_info "Waiting for DB instance to stop (this may take several minutes)..."
  rds_wait_for_instance_status "${db_instance_id}" "stopped" "${AWSTOOLS_RDS_STOP_WAIT_TIMEOUT}"
}

cmd_describe() {
  local db_instance_id="${1:-${AWSTOOLS_RDS_DEFAULT_INSTANCE_ID}}"
  if [[ -z "${db_instance_id}" ]]; then
    log_error "Usage: awstools rds describe <db-instance-identifier>"
    return 1
  fi
  log_info "Describing RDS instance: ${db_instance_id}"
  ensure_aws_ready
  rds_describe_instance "${db_instance_id}"
}

cmd_connect() {
  local db_instance_id="${1:-${AWSTOOLS_RDS_DEFAULT_INSTANCE_ID}}"
  if [[ -z "${db_instance_id}" ]]; then
    log_error "Usage: awstools rds connect <db-instance-identifier>"
    return 1
  fi

  ensure_aws_ready

  log_info "Setting up secure connection to RDS instance: ${db_instance_id}"

  # Get RDS connection information
  local connection_info
  connection_info=$(rds_get_connection_info "${db_instance_id}") || return 1

  local db_endpoint db_port db_engine db_name vpc_id
  db_endpoint=$(echo "${connection_info}" | jq -r '.Endpoint // empty')
  db_port=$(echo "${connection_info}" | jq -r '.Port // empty')
  db_engine=$(echo "${connection_info}" | jq -r '.Engine // empty')
  db_name=$(echo "${connection_info}" | jq -r '.DBName // empty')
  vpc_id=$(echo "${connection_info}" | jq -r '.VpcId // empty')

  if [[ -z "${db_endpoint}" ]] || [[ -z "${db_port}" ]]; then
    log_error "Could not retrieve connection information for DB instance: ${db_instance_id}"
    return 1
  fi

  log_info "Database details:"
  log_info "  Endpoint: ${db_endpoint}"
  log_info "  Port: ${db_port}"
  log_info "  Engine: ${db_engine}"
  [[ -n "${db_name}" ]] && log_info "  Database: ${db_name}"
  [[ -n "${vpc_id}" ]] && log_info "  VPC: ${vpc_id}"

  # Select bastion instance if not provided
  local instance_id="${BASTION_INSTANCE_ID:-${AWSTOOLS_RDS_SSM_DEFAULT_BASTION_INSTANCE_ID}}"
  if [[ -z "${instance_id}" ]]; then
    log_info ""
    log_info "Finding suitable bastion instances..."
    rds_list_bastion_instances "${vpc_id}"

    echo ""
    read -r -p "Enter EC2 instance ID to use as bastion: " instance_id

    if [[ -z "${instance_id}" ]]; then
      log_error "No instance ID provided"
      return 1
    fi
  fi

  # Validate bastion instance
  log_info "Validating bastion instance: ${instance_id}"
  if ! rds_check_ssm_connectivity "${instance_id}"; then
    log_error "Instance ${instance_id} is not suitable for Session Manager tunneling"
    log_info "Ensure the instance has:"
    log_info "  1. SSM Agent installed and running"
    log_info "  2. Appropriate IAM role with SSM permissions"
    log_info "  3. Network connectivity to the RDS instance"
    return 1
  fi

  log_info "✓ Instance ${instance_id} is ready for Session Manager"

  # Determine local port
  local local_port="${TUNNEL_LOCAL_PORT:-${AWSTOOLS_RDS_SSM_DEFAULT_LOCAL_PORT_START}}"
  if [[ -z "${local_port}" ]]; then
    local_port=$(find_available_port "${AWSTOOLS_RDS_SSM_LOCAL_PORT_START}") || return 1
    log_info "Using available local port: ${local_port}"
  else
    log_info "Using specified local port: ${local_port}"
  fi

  log_info ""
  log_info "=============================================="
  log_info "Session Manager Tunnel Setup"
  log_info "=============================================="
  log_info "Local port: ${local_port}"
  log_info "Target: ${db_endpoint}:${db_port}"
  log_info "Bastion: ${instance_id}"
  log_info ""
  log_info "After the tunnel is established, you can connect to:"
  log_info "  Host: localhost"
  log_info "  Port: ${local_port}"
  log_info ""
  log_info "Starting tunnel (press Ctrl+C to stop)..."
  log_info "=============================================="

  # Start the tunnel
  rds_start_ssm_tunnel "${instance_id}" "${db_endpoint}" "${db_port}" "${local_port}"
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
  connect)
    cmd_connect "$@"
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    log_error "Unknown command: ${COMMAND}"
    log_info "Run 'awstools rds help' for available commands"
    exit 1
    ;;
esac
