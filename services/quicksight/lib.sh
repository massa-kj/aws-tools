#!/usr/bin/env bash
#=============================================================
# lib.sh - Helper utilities for service
#=============================================================

set -euo pipefail

# Load common dependencies (idempotent loading)
if [[ -z "${EC2_LIB_LOADED:-}" ]]; then
  # Determine script directory and base directory
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
  COMMON_DIR="$BASE_DIR/common"

  # Load common configuration and utilities only once
  if [[ -z "${AWS_TOOLS_CONFIG_LOADED:-}" ]]; then
    source "$COMMON_DIR/config-loader.sh"
    export AWS_TOOLS_CONFIG_LOADED=1
  fi

  if [[ -z "${AWS_TOOLS_LOGGER_LOADED:-}" ]]; then
    source "$COMMON_DIR/logger.sh"
    export AWS_TOOLS_LOGGER_LOADED=1
  fi

  if [[ -z "${AWS_TOOLS_UTILS_LOADED:-}" ]]; then
    source "$COMMON_DIR/utils.sh"
    export AWS_TOOLS_UTILS_LOADED=1
  fi

  # Mark QuickSight lib as loaded to prevent double-loading
  export QuickService_LIB_LOADED=1

  log_debug "QuickSight lib.sh loaded (dependencies: config=${AWS_TOOLS_CONFIG_LOADED}, logger=${AWS_TOOLS_LOGGER_LOADED}, utils=${AWS_TOOLS_UTILS_LOADED})"
fi

#--- QuickSight-specific utility functions ----------------------------

filter_target_analyses() {
    local all_analyses="$1"
    local matched_analyses=()
    local analysis_ids=()
    
    for target_name in "${TARGET_ANALYSES[@]}"; do
        local matched_info
        matched_info=$(echo "$all_analyses" | jq -r --arg name "$target_name" \
            '.AnalysisSummaryList[] | select(.Name == $name) | "\(.Name)|\(.AnalysisId)|\(.CreatedTime // "N/A")|\(.LastUpdatedTime // "N/A")|\(.Status // "N/A")"')
        
        if [ -n "$matched_info" ]; then
            matched_analyses+=("$matched_info")
            local analysis_id
            analysis_id=$(echo "$matched_info" | cut -d'|' -f2)
            analysis_ids+=("$analysis_id")
        fi
    done
    
    if [ ${#matched_analyses[@]} -eq 0 ]; then
        log_error "Target analyses not found."
        log_info "Available analysis names:"
        echo "$all_analyses" | jq -r '.AnalysisSummaryList[].Name' | while read -r name; do
            echo "  - $name"
        done
        return 1
    fi
    
    # Set results to global variables
    MATCHED_ANALYSES=("${matched_analyses[@]}")
    ANALYSIS_IDS=("${analysis_ids[@]}")
}

filter_target_datasets() {
    local all_datasets="$1"
    local matched_datasets=()
    local dataset_ids=()
    
    for target_name in "${TARGET_DATASETS[@]}"; do
        local matched_info
        matched_info=$(echo "$all_datasets" | jq -r --arg name "$target_name" \
            '.DataSetSummaries[] | select(.Name == $name) | "\(.Name)|\(.DataSetId)|\(.CreatedTime // "N/A")|\(.LastUpdatedTime // "N/A")|\(.ImportMode // "N/A")"')
        
        if [ -n "$matched_info" ]; then
            matched_datasets+=("$matched_info")
            local dataset_id
            dataset_id=$(echo "$matched_info" | cut -d'|' -f2)
            dataset_ids+=("$dataset_id")
        fi
    done
    
    if [ ${#matched_datasets[@]} -eq 0 ]; then
        log_error "Target datasets not found."
        log_info "Available dataset names:"
        echo "$all_datasets" | jq -r '.DataSetSummaries[].Name' | while read -r name; do
            echo "  - $name"
        done
        return 1
    fi
    
    # Set results to global variables
    MATCHED_DATASETS=("${matched_datasets[@]}")
    DATASET_IDS=("${dataset_ids[@]}")
}

export_analyses() {
    local export_dir="$1"
    local success_count=0
    local error_count=0
    local export_summary=()
    
    log_info "Exporting analysis details..."
    
    # Create export directories
    mkdir -p "$export_dir/analyses"
    mkdir -p "$export_dir/definitions"
    mkdir -p "$export_dir/permissions"
    
    for analysis_info in "${MATCHED_ANALYSES[@]}"; do
        IFS='|' read -r analysis_name analysis_id created_time updated_time status <<< "$analysis_info"

        log_info "  Export: $analysis_name (ID: $analysis_id)"

        # Remove invalid characters from filename
        local safe_filename
        safe_filename=$(echo "$analysis_name" | sed 's/[\\/:*?"<>|]/_/g')
        
        # Get analysis basic information
        local analysis_detail
        if analysis_detail=$(aws_exec quicksight describe-analysis \
            --aws-account-id "$ACCOUNT_ID" \
            --analysis-id "$analysis_id" \
            --region "$AWS_REGION" \
            --output json 2>/dev/null); then
            
            echo "$analysis_detail" > "$export_dir/analyses/${safe_filename}-${analysis_id}.json"
            log_info "    ✓ Basic information saved"
            
        else
            log_error "    ✗ Basic information retrieval error: $analysis_name"
            ((error_count++))
            continue
        fi
        
        # Get analysis definition
        local analysis_definition sheet_count=0 visual_count=0
        if analysis_definition=$(aws_exec quicksight describe-analysis-definition \
            --aws-account-id "$ACCOUNT_ID" \
            --analysis-id "$analysis_id" \
            --region "$AWS_REGION" \
            --output json 2>/dev/null); then
            
            echo "$analysis_definition" > "$export_dir/definitions/${safe_filename}-${analysis_id}-definition.json"
            log_info "    ✓ Definition information saved"
            
            sheet_count=$(echo "$analysis_definition" | jq -r '.Definition.Sheets | length')
            visual_count=$(echo "$analysis_definition" | jq -r '.Definition.Sheets[].Visuals | length' | awk '{sum+=$1} END {print sum+0}')
            
        else
            log_error "    ✗ Definition information retrieval error: $analysis_name"
        fi
        
        # Get permission information
        if aws_exec quicksight describe-analysis-permissions \
            --aws-account-id "$ACCOUNT_ID" \
            --analysis-id "$analysis_id" \
            --region "$AWS_REGION" \
            --output json > "$export_dir/permissions/${safe_filename}-${analysis_id}-permissions.json" 2>/dev/null; then
            
            log_info "    ✓ Permission information saved"
        else
            log_error "    ✗ Permission information retrieval error: $analysis_name"
        fi
        
        # Extract dataset IDs
        local dataset_ids
        dataset_ids=$(echo "$analysis_detail" | jq -r '.Analysis.DataSetArns[]? // empty' | sed 's/.*dataset\///')
        
        export_summary+=("$analysis_name|$analysis_id|$status|${sheet_count:-0}|${visual_count:-0}|$dataset_ids")
        ((success_count++))
    done
    
    # Save summary information
    save_analysis_summary "$export_dir" "${export_summary[@]}"
    
    log_info "Analysis export completed: $success_count successful, $error_count errors"
    return $error_count
}

export_datasets() {
    local export_dir="$1"
    local success_count=0
    local error_count=0
    local export_summary=()
    
    log_info "Exporting dataset details..."
    
    # Create export directories
    mkdir -p "$export_dir/datasets"
    mkdir -p "$export_dir/permissions"
    
    for dataset_info in "${MATCHED_DATASETS[@]}"; do
        IFS='|' read -r dataset_name dataset_id created_time updated_time import_mode <<< "$dataset_info"
        
        log_info "  Export: $dataset_name (ID: $dataset_id)"
        
        # Remove invalid characters from filename
        local safe_filename
        safe_filename=$(echo "$dataset_name" | sed 's/[\\/:*?"<>|]/_/g')
        
        # Get dataset detailed information
        local dataset_detail
        if dataset_detail=$(aws_exec quicksight describe-data-set \
            --aws-account-id "$ACCOUNT_ID" \
            --data-set-id "$dataset_id" \
            --region "$AWS_REGION" \
            --output json 2>/dev/null); then
            
            echo "$dataset_detail" > "$export_dir/datasets/${safe_filename}-${dataset_id}.json"
            log_info "    ✓ Detailed information saved"
            
        else
            log_error "    ✗ Detailed information retrieval error: $dataset_name"
            ((error_count++))
            continue
        fi
        
        # Get permission information
        if aws_exec quicksight describe-data-set-permissions \
            --aws-account-id "$ACCOUNT_ID" \
            --data-set-id "$dataset_id" \
            --region "$AWS_REGION" \
            --output json > "$export_dir/permissions/${safe_filename}-${dataset_id}-permissions.json" 2>/dev/null; then
            
            log_info "    ✓ Permission information saved"
        else
            log_error "    ✗ Permission information retrieval error: $dataset_name"
        fi
        
        export_summary+=("$dataset_name|$dataset_id|$import_mode|$created_time|$updated_time")
        ((success_count++))
    done
    
    # Save summary information
    save_dataset_summary "$export_dir" "${export_summary[@]}"
    
    log_info "Dataset export completed: $success_count successful, $error_count errors"
    return $error_count
}

save_analysis_summary() {
    local export_dir="$1"
    shift
    local export_summary=("$@")
    
    # Save analysis ID list in JSON format
    if [ ${#ANALYSIS_IDS[@]} -gt 0 ]; then
        printf '["%s"' "${ANALYSIS_IDS[0]}" > "$export_dir/analysis-ids.json"
        for id in "${ANALYSIS_IDS[@]:1}"; do
            printf ',"%s"' "$id" >> "$export_dir/analysis-ids.json"
        done
        echo ']' >> "$export_dir/analysis-ids.json"
    fi
    
    # Create detailed analysis summary
    {
        echo "["
        for i in "${!export_summary[@]}"; do
            IFS='|' read -r name id status sheets visuals datasets <<< "${export_summary[i]}"
            
            if [ $i -eq $((${#export_summary[@]} - 1)) ]; then
                COMMA=""
            else
                COMMA=","
            fi
            
            cat << EOF
  {
    "Name": "$name",
    "AnalysisId": "$id",
    "Status": "$status",
    "SheetCount": $sheets,
    "VisualCount": $visuals,
    "DataSetIds": [$(echo "$datasets" | sed 's/\([^ ]*\)/"\1"/g' | tr ' ' ',')]
  }$COMMA
EOF
        done
        echo "]"
    } > "$export_dir/analysis-summary.json"
}

save_dataset_summary() {
    local export_dir="$1"
    shift
    local export_summary=("$@")
    
    # Save dataset ID list in JSON format
    if [ ${#DATASET_IDS[@]} -gt 0 ]; then
        printf '["%s"' "${DATASET_IDS[0]}" > "$export_dir/dataset-ids.json"
        for id in "${DATASET_IDS[@]:1}"; do
            printf ',"%s"' "$id" >> "$export_dir/dataset-ids.json"
        done
        echo ']' >> "$export_dir/dataset-ids.json"
    fi
    
    # Create detailed dataset summary
    {
        echo "["
        for i in "${!export_summary[@]}"; do
            IFS='|' read -r name id import_mode created_time updated_time <<< "${export_summary[i]}"
            
            if [ $i -eq $((${#export_summary[@]} - 1)) ]; then
                COMMA=""
            else
                COMMA=","
            fi
            
            cat << EOF
  {
    "Name": "$name",
    "DataSetId": "$id",
    "ImportMode": "$import_mode",
    "CreatedTime": "$created_time",
    "LastUpdatedTime": "$updated_time"
  }$COMMA
EOF
        done
        echo "]"
    } > "$export_dir/dataset-summary.json"
}

# Generate timestamped export directory name
generate_export_dir_name() {
    local type="$1"
    echo "quicksight-${type}-export-$(date +%Y%m%d-%H%M%S)"
}
