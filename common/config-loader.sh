#!/usr/bin/env bash

validate_config() {
  return 0
}

show_effective_config() {
  return 0
}

_load_config_layered() {
  local environment="$1"
  local service="$2"
  local base_dir="$3"
  local layer="$4" # "default" or "overwrite"
  
  # Common settings
  [ -f "$base_dir/${layer}/common.env" ] && source "$base_dir/${layer}/common.env"

  # AWS-Tools profile settings
  if [ -n "$environment" ]; then
    [ -f "$base_dir/${layer}/environments/${environment}.env" ] && source "$base_dir/${layer}/environments/${environment}.env"
    export AWSTOOLS_PROFILE="$environment"
  else
    [ -f "$base_dir/${layer}/environments/${AWSTOOLS_PROFILE}.env" ] && source "$base_dir/${layer}/environments/${AWSTOOLS_PROFILE}.env"
  fi

  # Service settings
  if [ -n "$service" ]; then
    [ -f "$base_dir/${layer}/services/${service}.env" ] && source "$base_dir/${layer}/services/${service}.env"
  fi

  return 0
}

load_config() {
  local environment="$1"
  local service="${2:-}"
  local base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../config" && pwd)"

  _load_config_layered "$environment" "$service" "$base_dir" "default"
  _load_config_layered "$environment" "$service" "$base_dir" "overwrite"

  return 0
}
