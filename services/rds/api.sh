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
