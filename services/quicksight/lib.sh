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

    for target_name in "${AWSTOOLS_QS_TARGET_ANALYSES[@]}"; do
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

    for target_name in "${AWSTOOLS_QS_TARGET_DATASETS[@]}"; do
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

# =============================================================
# Analysis creation / update helpers moved from legacy manager
# =============================================================

extract_analysis_params() {
    local json_file="$1"
    local temp_dir="$2"

    jq '.Analysis | del(.Arn, .CreatedTime, .LastUpdatedTime, .Status)' "$json_file" > "$temp_dir/create_params.json"
    if [ $? -ne 0 ]; then
        return 1
    fi
    echo "$temp_dir/create_params.json"
}

extract_analysis_definition() {
    local definition_file="$1"
    local temp_dir="$2"

    if [ ! -f "$definition_file" ]; then
        echo "null"
        return 0
    fi

    jq '.Definition // {}' "$definition_file" > "$temp_dir/definition.json"
    if [ $? -ne 0 ]; then
        return 1
    fi
    echo "$temp_dir/definition.json"
}

check_analysis_exists() {
    local analysis_id="$1"

    if aws_exec quicksight describe-analysis --aws-account-id "$ACCOUNT_ID" --analysis-id "$analysis_id" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

create_analysis() {
    local params_file="$1"
    local definition_file="$2"
    local dry_run="$3"

    local analysis_id analysis_name
    analysis_id=$(jq -r '.AnalysisId' "$params_file")
    analysis_name=$(jq -r '.Name' "$params_file")

    log_info "Creating analysis: $analysis_name (ID: $analysis_id)"

    if [ "$dry_run" = "true" ]; then
        log_warn "[DRY RUN] Will not perform actual creation"
        log_debug "Planned: aws quicksight create-analysis --aws-account-id $ACCOUNT_ID --analysis-id $analysis_id --name '$analysis_name' ..."
        return 0
    fi

    local args=(quicksight create-analysis --aws-account-id "$ACCOUNT_ID" --analysis-id "$analysis_id" --name "$analysis_name" --output json)

    if [ -f "$definition_file" ] && [ "$(jq -r '. | length' "$definition_file" 2>/dev/null)" != "0" ]; then
        args+=(--definition "file://$definition_file")
        log_debug "Using definition file: $definition_file"
    fi

    local theme_arn
    theme_arn=$(jq -r '.ThemeArn // empty' "$params_file")
    if [ -n "$theme_arn" ]; then
        args+=(--theme-arn "$theme_arn")
    fi

    if output=$(aws_exec "${args[@]}" 2>/dev/null); then
        log_info "✓ Analysis creation successful"
        log_debug "Result: $output"
        return 0
    else
        log_error "✗ Analysis creation failed"
        return 1
    fi
}

update_analysis() {
    local params_file="$1"
    local definition_file="$2"
    local dry_run="$3"

    local analysis_id analysis_name
    analysis_id=$(jq -r '.AnalysisId' "$params_file")
    analysis_name=$(jq -r '.Name' "$params_file")

    log_info "Updating analysis: $analysis_name (ID: $analysis_id)"

    if [ "$dry_run" = "true" ]; then
        log_warn "[DRY RUN] Will not perform actual update"
        log_debug "Planned: aws quicksight update-analysis --aws-account-id $ACCOUNT_ID --analysis-id $analysis_id --name '$analysis_name' ..."
        return 0
    fi

    local args=(quicksight update-analysis --aws-account-id "$ACCOUNT_ID" --analysis-id "$analysis_id" --name "$analysis_name" --output json)

    if [ -f "$definition_file" ] && [ "$(jq -r '. | length' "$definition_file" 2>/dev/null)" != "0" ]; then
        args+=(--definition "file://$definition_file")
        log_debug "Using definition file: $definition_file"
    fi

    local theme_arn
    theme_arn=$(jq -r '.ThemeArn // empty' "$params_file")
    if [ -n "$theme_arn" ]; then
        args+=(--theme-arn "$theme_arn")
    fi

    if output=$(aws_exec "${args[@]}" 2>/dev/null); then
        log_info "✓ Analysis update successful"
        log_debug "Result: $output"
        return 0
    else
        log_error "✗ Analysis update failed"
        return 1
    fi
}

update_analysis_permissions() {
    local analysis_id="$1"
    local permissions_file="$2"
    local dry_run="$3"

    if [ ! -f "$permissions_file" ]; then
        log_warn "Permissions file not found, skipping: $permissions_file"
        return 0
    fi

    log_info "Updating analysis permissions: $analysis_id"

    if [ "$dry_run" = "true" ]; then
        log_warn "[DRY RUN] Will not perform actual permission update"
        return 0
    fi

    local permissions
    permissions=$(jq -c '.Permissions // []' "$permissions_file" 2>/dev/null)

    if [ "$permissions" = "[]" ] || [ "$permissions" = "null" ]; then
        log_warn "No permissions configuration found, skipping"
        return 0
    fi

    if aws_exec quicksight update-analysis-permissions --aws-account-id "$ACCOUNT_ID" --analysis-id "$analysis_id" --grant-permissions "$permissions" >/dev/null 2>&1; then
        log_info "✓ Permissions update successful"
        return 0
    else
        log_error "✗ Permissions update failed"
        return 1
    fi
}

show_single_analysis_info() {
    local json_file="$1"
    local operation="$2"

    log_info "=== Processing Target Information ==="
    log_info "File: $json_file"

    local analysis_id analysis_name
    analysis_id=$(jq -r '.Analysis.AnalysisId // "N/A"' "$json_file" 2>/dev/null)
    analysis_name=$(jq -r '.Analysis.Name // "N/A"' "$json_file" 2>/dev/null)

    log_debug "Analysis ID: $analysis_id"
    log_debug "Analysis Name: $analysis_name"
    log_debug "Operation to execute: $operation"
}

show_multiple_analyses_info() {
    local target_dir="$1"
    local operation="$2"
    shift 2
    local json_files=("$@")

    log_info "=== Batch Processing Target Information ==="
    log_info "Target Directory: $target_dir"
    log_debug "Operation to execute: $operation"
    log_info "Number of files to process: ${#json_files[@]}"

    log_info "Processing target list:"
    local count=1
    for json_file in "${json_files[@]}"; do
        local analysis_id analysis_name
        analysis_id=$(jq -r '.Analysis.AnalysisId // "N/A"' "$json_file" 2>/dev/null)
        analysis_name=$(jq -r '.Analysis.Name // "N/A"' "$json_file" 2>/dev/null)

        printf "%2d. %s\n" "$count" "$(basename "$json_file")"
        log_debug "    ID: $analysis_id"
        log_debug "    Name: $analysis_name"
        echo
        ((count++))
    done
}

process_analysis_json() {
    local json_file="$1"
    local operation="$2"  # create|update|upsert
    local dry_run="$3"
    local update_permissions_flag="$4"
    local skip_confirmation="$5"

    if [ ! -f "$json_file" ]; then
        log_error "File not found: $json_file"
        return 1
    fi

    if [ "$skip_confirmation" != "true" ]; then
        show_single_analysis_info "$json_file" "$operation"
        if [ "$dry_run" != "true" ]; then
            if ! confirm_action "Will execute $operation operation on the above analysis."; then
                return 1
            fi
        fi
    fi

    log_info "=== Analysis Processing Started: $(basename "$json_file") ==="

    local temp_dir
    temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' EXIT

    local params_file
    if ! params_file=$(extract_analysis_params "$json_file" "$temp_dir"); then
        log_error "Failed to extract parameters"
        return 1
    fi

    local definition_file=""
    local base_dir
    base_dir=$(dirname "$json_file")
    local base_name
    base_name=$(basename "$json_file" .json)

    local potential_def_file="$base_dir/../definitions/${base_name}-definition.json"
    if [ -f "$potential_def_file" ]; then
        definition_file=$(extract_analysis_definition "$potential_def_file" "$temp_dir")
        log_debug "Definition file detected: $potential_def_file"
    else
        if jq -e '.Definition' "$json_file" >/dev/null 2>&1; then
            jq '.Definition' "$json_file" > "$temp_dir/definition.json"
            definition_file="$temp_dir/definition.json"
            log_debug "Using definition from JSON"
        fi
    fi

    local analysis_id analysis_name
    analysis_id=$(jq -r '.AnalysisId' "$params_file")
    analysis_name=$(jq -r '.Name' "$params_file")

    if [ -z "$analysis_id" ] || [ "$analysis_id" = "null" ]; then
        log_error "AnalysisId not found"
        return 1
    fi

    log_debug "Target analysis: $analysis_name (ID: $analysis_id)"

    local actual_operation="$operation"
    if [ "$operation" = "upsert" ]; then
        if check_analysis_exists "$analysis_id"; then
            actual_operation="update"
            log_warn "Existing analysis detected, switching to update mode"
        else
            actual_operation="create"
            log_warn "New analysis, switching to create mode"
        fi
    fi

    case $actual_operation in
        create)
            if check_analysis_exists "$analysis_id"; then
                log_error "Analysis already exists: $analysis_id"
                log_warn "Use --operation update to update it"
                return 1
            fi
            create_analysis "$params_file" "$definition_file" "$dry_run"
            ;;
        update)
            if ! check_analysis_exists "$analysis_id"; then
                log_error "Analysis does not exist: $analysis_id"
                log_warn "Use --operation create to create it"
                return 1
            fi
            update_analysis "$params_file" "$definition_file" "$dry_run"
            ;;
        *)
            log_error "Unknown operation: $actual_operation"
            return 1
            ;;
    esac

    local main_result=$?

    if [ $main_result -eq 0 ] && [ "$update_permissions_flag" = "true" ]; then
        local permissions_file="$base_dir/../permissions/${base_name}-permissions.json"
        update_analysis_permissions "$analysis_id" "$permissions_file" "$dry_run"
    fi

    if [ $main_result -eq 0 ]; then
        log_info "=== Processing Complete: Success ==="
    else
        log_error "=== Processing Complete: Error ==="
    fi

    return $main_result
}

process_multiple_analyses() {
    local target_dir="$1"
    local operation="$2"
    local dry_run="$3"
    local update_permissions_flag="$4"

    local json_files=()
    while IFS= read -r -d '' file; do
        if [[ "$file" != *"-permissions.json" ]] && [[ "$file" != *"-definition.json" ]]; then
            json_files+=("$file")
        fi
    done < <(find "$target_dir" -name "*.json" -print0 2>/dev/null)

    if [ ${#json_files[@]} -eq 0 ]; then
        log_error "No JSON files found"
        return 1
    fi

    show_multiple_analyses_info "$target_dir" "$operation" "${json_files[@]}"

    if [ "$dry_run" != "true" ]; then
        if ! confirm_action "Will batch execute $operation operation on the above ${#json_files[@]} analyses."; then
            return 1
        fi
    fi

    log_info "=== Batch Processing of Multiple Analyses Started ==="

    local success_count=0
    local error_count=0

    for json_file in "${json_files[@]}"; do
        echo
        if process_analysis_json "$json_file" "$operation" "$dry_run" "$update_permissions_flag" "true"; then
            ((success_count++))
        else
            ((error_count++))
        fi
    done

    echo
    log_info "=== Batch Processing Complete ==="
    log_info "Successful: $success_count items"
    [ $error_count -gt 0 ] && log_error "Errors: $error_count items"

    return $error_count
}

# =============================================================
# Dataset creation / update helpers moved from legacy manager
# =============================================================

extract_dataset_params() {
    local json_file="$1"
    local temp_dir="$2"

    jq '.DataSet | del(.Arn, .CreatedTime, .LastUpdatedTime, .OutputColumns, .ConsumedSpiceCapacityInBytes)' "$json_file" > "$temp_dir/create_params.json"
    if [ $? -ne 0 ]; then
        return 1
    fi
    echo "$temp_dir/create_params.json"
}

check_dataset_exists() {
    local dataset_id="$1"

    if aws_exec quicksight describe-data-set --aws-account-id "$ACCOUNT_ID" --data-set-id "$dataset_id" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

create_dataset() {
    local params_file="$1"
    local dry_run="$2"

    local dataset_id dataset_name
    dataset_id=$(jq -r '.DataSetId' "$params_file")
    dataset_name=$(jq -r '.Name' "$params_file")

    log_info "Creating dataset: $dataset_name (ID: $dataset_id)"

    if [ "$dry_run" = "true" ]; then
        log_warn "[DRY RUN] Will not perform actual creation"
        log_debug "Planned: aws quicksight create-data-set --aws-account-id $ACCOUNT_ID --data-set-id $dataset_id --cli-input-json file://$params_file"
        return 0
    fi

    if output=$(aws_exec quicksight create-data-set --aws-account-id "$ACCOUNT_ID" --data-set-id "$dataset_id" --cli-input-json "file://$params_file" --output json 2>/dev/null); then
        log_info "✓ Dataset creation successful"
        log_debug "Result: $output"
        return 0
    else
        log_error "✗ Dataset creation failed"
        return 1
    fi
}

update_dataset() {
    local params_file="$1"
    local dry_run="$2"

    local dataset_id dataset_name
    dataset_id=$(jq -r '.DataSetId' "$params_file")
    dataset_name=$(jq -r '.Name' "$params_file")

    log_info "Updating dataset: $dataset_name (ID: $dataset_id)"

    if [ "$dry_run" = "true" ]; then
        log_warn "[DRY RUN] Will not perform actual update"
        log_debug "Planned: aws quicksight update-data-set --aws-account-id $ACCOUNT_ID --data-set-id $dataset_id --cli-input-json file://$params_file"
        return 0
    fi

    if output=$(aws_exec quicksight update-data-set --aws-account-id "$ACCOUNT_ID" --data-set-id "$dataset_id" --cli-input-json "file://$params_file" --output json 2>/dev/null); then
        log_info "✓ Dataset update successful"
        log_debug "Result: $output"
        return 0
    else
        log_error "✗ Dataset update failed"
        return 1
    fi
}

update_dataset_permissions() {
    local dataset_id="$1"
    local permissions_file="$2"
    local dry_run="$3"

    if [ ! -f "$permissions_file" ]; then
        log_warn "Permissions file not found, skipping: $permissions_file"
        return 0
    fi

    log_info "Updating dataset permissions: $dataset_id"

    if [ "$dry_run" = "true" ]; then
        log_warn "[DRY RUN] Will not perform actual permission update"
        return 0
    fi

    local permissions
    permissions=$(jq -c '.Permissions // []' "$permissions_file" 2>/dev/null)

    if [ "$permissions" = "[]" ] || [ "$permissions" = "null" ]; then
        log_warn "No permissions configuration found, skipping"
        return 0
    fi

    if aws_exec quicksight update-data-set-permissions --aws-account-id "$ACCOUNT_ID" --data-set-id "$dataset_id" --grant-permissions "$permissions" >/dev/null 2>&1; then
        log_info "✓ Permissions update successful"
        return 0
    else
        log_error "✗ Permissions update failed"
        return 1
    fi
}

show_single_dataset_info() {
    local json_file="$1"
    local operation="$2"

    log_info "=== Processing Target Information ==="
    log_info "File: $json_file"

    local dataset_id dataset_name
    dataset_id=$(jq -r '.DataSet.DataSetId // "N/A"' "$json_file" 2>/dev/null)
    dataset_name=$(jq -r '.DataSet.Name // "N/A"' "$json_file" 2>/dev/null)

    log_debug "Dataset ID: $dataset_id"
    log_debug "Dataset Name: $dataset_name"
    log_debug "Operation to execute: $operation"
}

show_multiple_datasets_info() {
    local target_dir="$1"
    local operation="$2"
    shift 2
    local json_files=("$@")

    log_info "=== Batch Processing Target Information ==="
    log_info "Target Directory: $target_dir"
    log_debug "Operation to execute: $operation"
    log_info "Number of files to process: ${#json_files[@]}"

    log_info "Processing target list:"
    local count=1
    for json_file in "${json_files[@]}"; do
        local dataset_id dataset_name
        dataset_id=$(jq -r '.DataSet.DataSetId // "N/A"' "$json_file" 2>/dev/null)
        dataset_name=$(jq -r '.DataSet.Name // "N/A"' "$json_file" 2>/dev/null)

        printf "%2d. %s\n" "$count" "$(basename "$json_file")"
        log_debug "    ID: $dataset_id"
        log_debug "    Name: $dataset_name"
        echo
        ((count++))
    done
}

process_dataset_json() {
    local json_file="$1"
    local operation="$2"  # create|update|upsert
    local dry_run="$3"
    local update_permissions_flag="$4"
    local skip_confirmation="$5"

    if [ ! -f "$json_file" ]; then
        log_error "File not found: $json_file"
        return 1
    fi

    if [ "$skip_confirmation" != "true" ]; then
        show_single_dataset_info "$json_file" "$operation"
        if [ "$dry_run" != "true" ]; then
            if ! confirm_action "Will execute $operation operation on the above dataset."; then
                return 1
            fi
        fi
    fi

    log_info "=== Dataset Processing Started: $(basename "$json_file") ==="

    local temp_dir
    temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' EXIT

    local params_file
    if ! params_file=$(extract_dataset_params "$json_file" "$temp_dir"); then
        log_error "Failed to extract parameters"
        return 1
    fi

    local dataset_id dataset_name
    dataset_id=$(jq -r '.DataSetId' "$params_file")
    dataset_name=$(jq -r '.Name' "$params_file")

    if [ -z "$dataset_id" ] || [ "$dataset_id" = "null" ]; then
        log_error "DataSetId not found"
        return 1
    fi

    log_debug "Target dataset: $dataset_name (ID: $dataset_id)"

    local actual_operation="$operation"
    if [ "$operation" = "upsert" ]; then
        if check_dataset_exists "$dataset_id"; then
            actual_operation="update"
            log_warn "Existing dataset detected, switching to update mode"
        else
            actual_operation="create"
            log_warn "New dataset, switching to create mode"
        fi
    fi

    case $actual_operation in
        create)
            if check_dataset_exists "$dataset_id"; then
                log_error "Dataset already exists: $dataset_id"
                log_warn "Use --operation update to update it"
                return 1
            fi
            create_dataset "$params_file" "$dry_run"
            ;;
        update)
            if ! check_dataset_exists "$dataset_id"; then
                log_error "Dataset does not exist: $dataset_id"
                log_warn "Use --operation create to create it"
                return 1
            fi
            update_dataset "$params_file" "$dry_run"
            ;;
        *)
            log_error "Unknown operation: $actual_operation"
            return 1
            ;;
    esac

    local main_result=$?

    if [ $main_result -eq 0 ] && [ "$update_permissions_flag" = "true" ]; then
        local permissions_file
        permissions_file=$(dirname "$json_file")/../permissions/$(basename "$json_file" .json)-permissions.json
        update_dataset_permissions "$dataset_id" "$permissions_file" "$dry_run"
    fi

    if [ $main_result -eq 0 ]; then
        log_info "=== Processing Complete: Success ==="
    else
        log_error "=== Processing Complete: Error ==="
    fi

    return $main_result
}

process_multiple_datasets() {
    local target_dir="$1"
    local operation="$2"
    local dry_run="$3"
    local update_permissions_flag="$4"

    local json_files=()
    while IFS= read -r -d '' file; do
        if [[ "$file" != *"-permissions.json" ]]; then
            json_files+=("$file")
        fi
    done < <(find "$target_dir" -name "*.json" -print0 2>/dev/null)

    if [ ${#json_files[@]} -eq 0 ]; then
        log_error "No JSON files found"
        return 1
    fi

    show_multiple_datasets_info "$target_dir" "$operation" "${json_files[@]}"

    if [ "$dry_run" != "true" ]; then
        if ! confirm_action "Will batch execute $operation operation on the above ${#json_files[@]} datasets."; then
            return 1
        fi
    fi

    log_info "=== Batch Processing of Multiple Datasets Started ==="

    local success_count=0
    local error_count=0

    for json_file in "${json_files[@]}"; do
        echo
        if process_dataset_json "$json_file" "$operation" "$dry_run" "$update_permissions_flag" "true"; then
            ((success_count++))
        else
            ((error_count++))
        fi
    done

    echo
    log_info "=== Batch Processing Complete ==="
    log_info "Successful: $success_count items"
    [ $error_count -gt 0 ] && log_error "Errors: $error_count items"

    return $error_count
}
