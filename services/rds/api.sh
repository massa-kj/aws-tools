#!/usr/bin/env bash
#=============================================================
# api.sh - Low-level AWS CLI wrappers for RDS
#=============================================================

set -euo pipefail

# Load dependencies (explicit loading for clarity and testability)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

#--- List RDS instances -----------------------------------------
rds_list_instances() {
  log_debug "Fetching RDS instance list..."
  aws_exec rds describe-db-instances \
    --query "DBInstances[].{ID:DBInstanceIdentifier,Status:DBInstanceStatus,Engine:Engine,Class:DBInstanceClass,Name:DBName}" \
    --output table
}

#--- Start RDS instance ------------------------------------------
rds_start_instance() {
  local db_instance_id="${1:-}"
  if [ -z "$db_instance_id" ]; then
    log_error "Usage: rds_start_instance <db-instance-identifier>"
    return 1
  fi

  validate_db_instance_id "$db_instance_id" || return 1

  log_info "Starting DB instance: $db_instance_id"
  aws_exec rds start-db-instance --db-instance-identifier "$db_instance_id" >/dev/null
  log_info "Start command sent successfully."
}

#--- Stop RDS instance -------------------------------------------
rds_stop_instance() {
  local db_instance_id="${1:-}"
  if [ -z "$db_instance_id" ]; then
    log_error "Usage: rds_stop_instance <db-instance-identifier>"
    return 1
  fi

  validate_db_instance_id "$db_instance_id" || return 1

  log_info "Stopping DB instance: $db_instance_id"
  aws_exec rds stop-db-instance --db-instance-identifier "$db_instance_id" >/dev/null
  log_info "Stop command sent successfully."
}

#--- Describe RDS instance ---------------------------------------
rds_describe_instance() {
  local db_instance_id="${1:-}"
  if [ -z "$db_instance_id" ]; then
    log_error "Usage: rds_describe_instance <db-instance-identifier>"
    return 1
  fi

  validate_db_instance_id "$db_instance_id" || return 1

  log_debug "Fetching detailed information for DB instance: $db_instance_id"
  aws_exec rds describe-db-instances \
    --db-instance-identifier "$db_instance_id" \
    --query 'DBInstances[0].{
      DBInstanceIdentifier:DBInstanceIdentifier,
      Status:DBInstanceStatus,
      Engine:Engine,
      EngineVersion:EngineVersion,
      DBInstanceClass:DBInstanceClass,
      DBName:DBName,
      Endpoint:Endpoint.Address,
      Port:Endpoint.Port,
      AllocatedStorage:AllocatedStorage,
      InstanceCreateTime:InstanceCreateTime
    }' \
    --output table
}

#--- Get DB instance status --------------------------------------
rds_get_instance_status() {
  local db_instance_id="$1"
  validate_db_instance_id "$db_instance_id" || return 1

  log_debug "Getting status for DB instance: $db_instance_id"
  aws_exec rds describe-db-instances \
    --db-instance-identifier "$db_instance_id" \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text
}

#--- Wait for DB instance status change -------------------------
rds_wait_for_instance_status() {
  local db_instance_id="$1"
  local target_status="$2"
  local timeout="${3:-600}"  # 10 minutes default (RDS operations are slower)

  validate_db_instance_id "$db_instance_id" || return 1

  log_info "Waiting for DB instance $db_instance_id to reach status: $target_status (timeout: ${timeout}s)"

  local elapsed=0
  while [ $elapsed -lt $timeout ]; do
    local current_status
    current_status=$(rds_get_instance_status "$db_instance_id")

    if [ "$current_status" = "$target_status" ]; then
      log_info "DB instance $db_instance_id is now in status: $target_status"
      return 0
    fi

    log_debug "Current status: $current_status, waiting..."
    sleep 30  # RDS operations are slower, check less frequently
    elapsed=$((elapsed + 30))
  done

  log_error "Timeout waiting for DB instance $db_instance_id to reach status $target_status"
  return 1
}

#--- Get RDS instance connection details -------------------------
rds_get_connection_info() {
  local db_instance_id="$1"
  validate_db_instance_id "$db_instance_id" || return 1

  log_debug "Getting connection info for DB instance: $db_instance_id"
  aws_exec rds describe-db-instances \
    --db-instance-identifier "$db_instance_id" \
    --query 'DBInstances[0].{
      Endpoint:Endpoint.Address,
      Port:Endpoint.Port,
      Engine:Engine,
      DBName:DBName,
      VpcId:DBSubnetGroup.VpcId,
      SecurityGroups:VpcSecurityGroups[0].VpcSecurityGroupId
    }' \
    --output json
}

#--- List EC2 instances that can act as bastion hosts -----------
rds_list_bastion_instances() {
  local vpc_id="${1:-}"

  log_debug "Listing potential bastion EC2 instances..."

  local filter_args=()
  filter_args+=(--filters "Name=state,Values=running")

  if [ -n "$vpc_id" ]; then
    filter_args+=(--filters "Name=vpc-id,Values=$vpc_id")
  fi

  aws_exec ec2 describe-instances \
    "${filter_args[@]}" \
    --query 'Reservations[].Instances[].[
      InstanceId,
      Tags[?Key==`Name`].Value|[0],
      PrivateIpAddress,
      PublicIpAddress,
      VpcId,
      SubnetId,
      State.Name
    ]' \
    --output table
}

#--- Check if EC2 instance has SSM agent running ----------------
rds_check_ssm_connectivity() {
  local instance_id="$1"

  if [ -z "$instance_id" ]; then
    log_error "Usage: rds_check_ssm_connectivity <instance-id>"
    return 1
  fi

  log_debug "Checking SSM connectivity for instance: $instance_id"

  # Check if instance is managed by SSM
  local ssm_status
  ssm_status=$(aws_exec ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$instance_id" \
    --query 'InstanceInformationList[0].PingStatus' \
    --output text 2>/dev/null)

  if [ "$ssm_status" = "Online" ]; then
    return 0
  else
    log_warn "Instance $instance_id is not online in SSM (status: ${ssm_status:-Not Found})"
    return 1
  fi
}

#--- Start Session Manager port forwarding ----------------------
rds_start_ssm_tunnel() {
  local instance_id="$1"
  local db_endpoint="$2"
  local db_port="$3"
  local local_port="${4:-5432}"

  if [ -z "$instance_id" ] || [ -z "$db_endpoint" ] || [ -z "$db_port" ]; then
    log_error "Usage: rds_start_ssm_tunnel <instance-id> <db-endpoint> <db-port> [local-port]"
    return 1
  fi

  # Check if local port is available
  if command -v netstat >/dev/null 2>&1; then
    if netstat -ln | grep -q ":$local_port "; then
      log_error "Local port $local_port is already in use"
      return 1
    fi
  fi

  log_info "Starting Session Manager tunnel:"
  log_info "  Instance: $instance_id"
  log_info "  Target: $db_endpoint:$db_port"
  log_info "  Local port: $local_port"
  log_info ""
  log_info "Session Manager will start in the background..."
  log_info "Press Ctrl+C to stop the tunnel when done."

  # Start the session manager port forwarding
  aws_exec ssm start-session \
    --target "$instance_id" \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters "{
      \"host\":[\"$db_endpoint\"],
      \"portNumber\":[\"$db_port\"],
      \"localPortNumber\":[\"$local_port\"]
    }"
}
