#!/usr/bin/env bash
#=============================================================
# api.sh - Low-level AWS CLI wrappers
#=============================================================

set -euo pipefail

# Load dependencies (explicit loading for clarity and testability)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

#--- List EC2 instances -----------------------------------------
ec2_list_instances() {
  log_debug "Fetching EC2 instance list..."
  aws_exec ec2 describe-instances \
    --query "Reservations[].Instances[].{ID:InstanceId,State:State.Name,Name:Tags[?Key=='Name'].Value|[0],Type:InstanceType}" \
    --output table
}

#--- Start EC2 instance ------------------------------------------
ec2_start_instance() {
  local instance_id="${1:-}"
  if [ -z "$instance_id" ]; then
    log_error "Usage: ec2_start_instance <instance-id>"
    return 1
  fi

  validate_instance_id "$instance_id" || return 1

  log_info "Starting instance: $instance_id"
  aws_exec ec2 start-instances --instance-ids "$instance_id" >/dev/null
  log_info "Start command sent successfully."
}

#--- Stop EC2 instance -------------------------------------------
ec2_stop_instance() {
  local instance_id="${1:-}"
  if [ -z "$instance_id" ]; then
    log_error "Usage: ec2_stop_instance <instance-id>"
    return 1
  fi

  validate_instance_id "$instance_id" || return 1

  log_info "Stopping instance: $instance_id"
  aws_exec ec2 stop-instances --instance-ids "$instance_id" >/dev/null
  log_info "Stop command sent successfully."
}

#--- Describe EC2 instance ---------------------------------------
ec2_describe_instance() {
  local instance_id="${1:-}"
  if [ -z "$instance_id" ]; then
    log_error "Usage: ec2_describe_instance <instance-id>"
    return 1
  fi

  validate_instance_id "$instance_id" || return 1

  log_debug "Fetching detailed information for instance: $instance_id"
  aws_exec ec2 describe-instances \
    --instance-ids "$instance_id" \
    --query 'Reservations[0].Instances[0].{
      InstanceId:InstanceId,
      State:State.Name,
      InstanceType:InstanceType,
      Name:Tags[?Key==`Name`].Value|[0],
      PublicIP:PublicIpAddress,
      PrivateIP:PrivateIpAddress,
      LaunchTime:LaunchTime
    }' \
    --output table
}

#--- Get instance state ------------------------------------------
ec2_get_instance_state() {
  local instance_id="$1"
  validate_instance_id "$instance_id" || return 1

  log_debug "Getting state for instance: $instance_id"
  aws_exec ec2 describe-instances \
    --instance-ids "$instance_id" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text
}

#--- Wait for instance state change ------------------------------
ec2_wait_for_instance_state() {
  local instance_id="$1"
  local target_state="$2"
  local timeout="${3:-300}"  # 5 minutes default

  validate_instance_id "$instance_id" || return 1

  log_info "Waiting for instance $instance_id to reach state: $target_state (timeout: ${timeout}s)"

  local elapsed=0
  while [ $elapsed -lt $timeout ]; do
    local current_state
    current_state=$(ec2_get_instance_state "$instance_id")

    if [ "$current_state" = "$target_state" ]; then
      log_info "Instance $instance_id is now in state: $target_state"
      return 0
    fi

    log_debug "Current state: $current_state, waiting..."
    sleep 10
    elapsed=$((elapsed + 10))
  done

  log_error "Timeout waiting for instance $instance_id to reach state $target_state"
  return 1
}
