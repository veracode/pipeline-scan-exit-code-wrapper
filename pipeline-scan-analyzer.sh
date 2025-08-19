#!/bin/bash

# Veracode Pipeline-Scan Wrapper
# This script acts as a wrapper around any command, running it and analyzing
# the output only when the command exits with code 255 (indicating an error).

set -o pipefail

# Default values
CONFIG_FILE="patterns.conf"
VERBOSE=false
DRY_RUN=false
JSON_OUTPUT="veracode-pipeline-scan-wrapper.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS] -- <command>

Wrapper script that runs a command and analyzes its output for specific patterns
when the command exits with code 255.

OPTIONS:
    -c, --config FILE    Configuration file with patterns (default: patterns.conf)
    -v, --verbose        Enable verbose output
    -d, --dry-run        Show what would be done without exiting
    -h, --help           Show this help message

ARGUMENTS:
    command              The command to run (must be preceded by --)

EXIT CODES:
    0: PASS - no flaws found (under current thresholds)
    1-200: FAIL - flaws found; value = count
    255: Command failed, patterns analyzed
    -10 to -79: Granular error codes (only when original command exits with 255)
    100: Configuration file not found
    101: Invalid command format

EXAMPLES:
    $0 -- veracode-pipeline-scan --file app.zip
    $0 -c custom_patterns.conf -- veracode-pipeline-scan --verbose
    $0 --dry-run -- echo "test command"
    $0 --help

EOF
}

# Function to print colored output
print_status() {
    local level="$1"
    local message="$2"
    
    case "$level" in
        "INFO")
            echo -e "${BLUE}[WRAPPER]${NC} $message" >&2
            ;;
        "WARN")
            echo -e "${YELLOW}[WRAPPER]${NC} $message" >&2
            ;;
        "ERROR")
            echo -e "${RED}[WRAPPER]${NC} $message" >&2
            ;;
        "SUCCESS")
            echo -e "${GREEN}[WRAPPER]${NC} $message" >&2
            ;;
        *)
            echo "[WRAPPER] $message" >&2
            ;;
    esac
}

# Function to validate configuration file
validate_config() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        print_status "ERROR" "Configuration file '$config_file' not found"
        exit 100
    fi
    
    if [[ ! -r "$config_file" ]]; then
        print_status "ERROR" "Configuration file '$config_file' is not readable"
        exit 100
    fi
    
    # Check if file is empty
    if [[ ! -s "$config_file" ]]; then
        print_status "ERROR" "Configuration file '$config_file' is empty"
        exit 100
    fi
    
    print_status "INFO" "Configuration file '$config_file' validated" >&2
}

# Function to check if grep supports -P (Perl regex)
check_grep_support() {
    if grep -P "test" /dev/null 2>/dev/null; then
        echo "perl"
    elif grep -E "test" /dev/null 2>/dev/null; then
        echo "extended"
    else
        echo "basic"
    fi
}

# Function to parse severity counts from command output
parse_severity_counts() {
    local output_file="$1"
    
    # Initialize severity counts
    local very_high=0
    local high=0
    local medium=0
    local low=0
    local info=0
    
    # Parse severity counts from output
    if [[ -f "$output_file" ]]; then
        # Look for "Found X issues of [Severity] severity" patterns
        very_high=$(grep -c "Found.*issues of Very High severity" "$output_file" 2>/dev/null || echo "0")
        high=$(grep -c "Found.*issues of High severity" "$output_file" 2>/dev/null || echo "0")
        medium=$(grep -c "Found.*issues of Medium severity" "$output_file" 2>/dev/null || echo "0")
        low=$(grep -c "Found.*issues of Low severity" "$output_file" 2>/dev/null || echo "0")
        info=$(grep -c "Found.*issues of Informational severity" "$output_file" 2>/dev/null || echo "0")
        
        # If we found severity patterns, extract the actual counts
        if [[ "$very_high" -gt 0 ]]; then
            very_high=$(grep "Found.*issues of Very High severity" "$output_file" | grep -o "Found [0-9]*" | grep -o "[0-9]*" | head -1 || echo "0")
        fi
        if [[ "$high" -gt 0 ]]; then
            high=$(grep "Found.*issues of High severity" "$output_file" | grep -o "Found [0-9]*" | grep -o "[0-9]*" | head -1 || echo "0")
        fi
        if [[ "$medium" -gt 0 ]]; then
            medium=$(grep "Found.*issues of Medium severity" "$output_file" | grep -o "Found [0-9]*" | grep -o "[0-9]*" | head -1 || echo "0")
        fi
        if [[ "$low" -gt 0 ]]; then
            low=$(grep "Found.*issues of Low severity" "$output_file" | grep -o "Found [0-9]*" | grep -o "[0-9]*" | head -1 || echo "0")
        fi
        if [[ "$info" -gt 0 ]]; then
            info=$(grep "Found.*issues of Informational severity" "$output_file" | grep -o "Found [0-9]*" | grep -o "[0-9]*" | head -1 || echo "0")
        fi
    fi
    
    # Return JSON-formatted severity counts
    echo "{\"very_high\": $very_high, \"high\": $high, \"medium\": $medium, \"low\": $low, \"info\": $info}"
}

# Function to generate JSON output
generate_json_output() {
    local exit_code="$1"
    local reason_code="$2"
    local disposition="$3"
    local summary="$4"
    local output_file="$5"
    local start_time="$6"
    local pattern_name="$7"
    local pattern_regex="$8"
    local pattern_count="$9"
    
    # Calculate timing
    local end_time=$(date +%s)
    local total_ms=$(((end_time - start_time) * 1000))
    
    # Determine disposition and reason code
    local final_disposition="$disposition"
    local final_reason_code="$reason_code"
    
    # Extract flaw count if available (for exit codes 1-200)
    local flaw_count=0
    local severity_counts='{"very_high": 0, "high": 0, "medium": 0, "low": 0, "info": 0}'
    
    if [[ "$exit_code" -ge 1 && "$exit_code" -le 200 ]]; then
        flaw_count="$exit_code"
        # Parse actual severity counts from command output
        severity_counts=$(parse_severity_counts "$output_file" | tr -d '\n')
    fi
    
    # Get environment variables for context
    local event="${GITHUB_EVENT_NAME:-${CI_PIPELINE_SOURCE:-unknown}}"
    local repo="${GITHUB_REPOSITORY:-${CI_PROJECT_PATH:-unknown}}"
    local commit="${GITHUB_SHA:-${CI_COMMIT_SHA:-unknown}}"
    local branch="${GITHUB_REF_NAME:-${CI_COMMIT_REF_NAME:-unknown}}"
    
    # Get last 20 lines of output for raw data
    local stdout_tail="[]"
    local stderr_tail="[]"
    
    if [[ -f "$output_file" ]]; then
        # Get last 20 lines of command output
        local output_lines
        if output_lines=$(tail -20 "$output_file" 2>/dev/null); then
            stdout_tail=$(echo "$output_lines" | jq -R -s 'split("\n")[:-1]' 2>/dev/null || echo "[]")
        fi
    fi
    
    # Create JSON structure with conditional pattern_match section
    local pattern_section=""
    if [[ -n "$pattern_name" ]]; then
        pattern_section=",
    \"pattern_match\": {
        \"name\": \"$pattern_name\",
        \"regex\": \"$pattern_regex\",
        \"count\": $pattern_count
    }"
    fi
    
    local json_output=$(cat << EOF
{
    "tool": "veracode-pipeline-scan",
    "version": "wrapper-1.0",
    "disposition": "$final_disposition",
    "exit_code": $exit_code,
    "reason_code": "$final_reason_code",
    "summary": "$summary",
    "flaw_count": $flaw_count,
    "severity_counts": $severity_counts,
    "timing": {
        "total_ms": $total_ms
    },
    "context": {
        "event": "$event",
        "repo": "$repo",
        "commit": "$commit",
        "branch": "$branch"
    }$pattern_section,
    "raw": {
        "stdout_tail": $stdout_tail,
        "stderr_tail": $stderr_tail
    }
}
EOF
)
    
    # Output JSON to file
    echo "$json_output" > "$JSON_OUTPUT"
    print_status "INFO" "JSON output written to: $JSON_OUTPUT" >&2
    
    # Also output to stderr for debugging
    if [[ "$VERBOSE" == "true" ]]; then
        print_status "DEBUG" "JSON output:" >&2
        echo "$json_output" >&2
    fi
}

# Function to process patterns and find matches
process_patterns() {
    local config_file="$1"
    local output_file="$2"
    local grep_type="$3"
    
    local highest_exit_code=0
    local found_matches=false
    local matched_pattern_name=""
    local matched_pattern_regex=""
    local matched_pattern_count=0
    
    print_status "INFO" "Processing patterns from configuration..." >&2
    
    # Read configuration file line by line
    while IFS='|' read -r pattern_name regex_pattern exit_code; do
        # Skip comments and empty lines
        [[ "$pattern_name" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$pattern_name" ]] && continue
        
        # Validate line format
        if [[ -z "$regex_pattern" || -z "$exit_code" ]]; then
            print_status "WARN" "Skipping invalid line: $pattern_name|$regex_pattern|$exit_code" >&2
            continue
        fi
        
        # Validate exit code is numeric (including negative numbers)
        if ! [[ "$exit_code" =~ ^-?[0-9]+$ ]]; then
            print_status "WARN" "Invalid exit code '$exit_code' for pattern '$pattern_name', skipping" >&2
            continue
        fi
        
        # Search for pattern in output file
        local matches=0
        case "$grep_type" in
            "perl")
                matches=$(grep -cP "$regex_pattern" "$output_file" 2>/dev/null 2>/dev/null || echo "0")
                ;;
            "extended")
                matches=$(grep -cE "$regex_pattern" "$output_file" 2>/dev/null 2>/dev/null || echo "0")
                ;;
            "basic")
                matches=$(grep -c "$regex_pattern" "$output_file" 2>/dev/null 2>/dev/null || echo "0")
                ;;
        esac
        
        # Validate that matches is a number
        if ! [[ "$matches" =~ ^[0-9]+$ ]]; then
            matches=0
        fi
        
                    if [[ "$matches" -gt 0 ]]; then
                found_matches=true
                
                # For negative exit codes, we want the "most negative" (lowest value)
                # For positive exit codes, we want the highest value
                if [[ "$exit_code" -lt 0 && "$highest_exit_code" -ge 0 ]]; then
                    # First negative code found, use it
                    highest_exit_code="$exit_code"
                    matched_pattern_name="$pattern_name"
                    matched_pattern_regex="$regex_pattern"
                    matched_pattern_count="$matches"
                elif [[ "$exit_code" -lt 0 && "$highest_exit_code" -lt 0 && "$exit_code" -lt "$highest_exit_code" ]]; then
                    # Both negative, use the more negative (lower) value
                    highest_exit_code="$exit_code"
                    matched_pattern_name="$pattern_name"
                    matched_pattern_regex="$regex_pattern"
                    matched_pattern_count="$matches"
                elif [[ "$exit_code" -gt 0 && "$highest_exit_code" -ge 0 && "$exit_code" -gt "$highest_exit_code" ]]; then
                    # Both positive, use the higher value
                    highest_exit_code="$exit_code"
                    matched_pattern_name="$pattern_name"
                    matched_pattern_regex="$regex_pattern"
                    matched_pattern_count="$matches"
                fi
            
            if [[ "$VERBOSE" == "true" ]]; then
                print_status "INFO" "Pattern '$pattern_name' matched $matches time(s) (exit code: $exit_code)" >&2
            fi
        fi
    done < "$config_file"
    
    # Return results
    if [[ "$found_matches" == "false" ]]; then
        echo "NO_MATCHES"
    else
        echo "{\"exit_code\":\"$highest_exit_code\",\"pattern_name\":\"$matched_pattern_name\",\"pattern_regex\":\"$matched_pattern_regex\",\"pattern_count\":\"$matched_pattern_count\"}"
    fi
}

# Function to run command and capture output
run_command() {
    local output_file="$1"
    shift
    
    print_status "INFO" "Running command: $*" >&2
    print_status "INFO" "Command output will be displayed below:" >&2
    echo "----------------------------------------" >&2
    
    # Run the command and capture output to file while also displaying it
    # Use tee to both display and save the output
    # Only capture the command output, not the script output
    print_status "DEBUG" "Executing command: $*" >&2
    
    # Execute command and capture output, ensuring it's displayed to terminal
    # The tee command will display to stdout and save to file
    if "$@" 2>&1 | tee "$output_file"; then
        local exit_code=${PIPESTATUS[0]}
    else
        local exit_code=${PIPESTATUS[0]}
    fi
    
    print_status "DEBUG" "Command execution completed with exit code: $exit_code" >&2
    
    # Output the exit code to stderr so it doesn't interfere with the command output
    echo "----------------------------------------" >&2
    print_status "INFO" "Command completed with exit code: $exit_code" >&2
    
    # Return exit code via exit status
    return "$exit_code"
}

# Main function
main() {
    local command_args=()
    local command_started=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --)
                command_started=true
                shift
                ;;
            -*)
                if [[ "$command_started" == "true" ]]; then
                    # This is part of the command, not an option
                    command_args+=("$1")
                else
                        print_status "ERROR" "Unknown option: $1" >&2
    usage
    exit 1
                fi
                shift
                ;;
            *)
                if [[ "$command_started" == "true" ]]; then
                    # This is part of the command
                    command_args+=("$1")
                else
                                        print_status "ERROR" "Command must be preceded by --" >&2
    usage
    exit 101
                fi
                shift
                ;;
        esac
    done
    
    # Check if command was provided
    if [[ ${#command_args[@]} -eq 0 ]]; then
                print_status "ERROR" "No command specified" >&2
    usage
    exit 101
    fi
    
    print_status "INFO" "Starting Veracode Pipeline-Scan Wrapper..." >&2
    print_status "INFO" "Configuration file: $CONFIG_FILE" >&2
    print_status "INFO" "Command: ${command_args[*]}" >&2
    print_status "INFO" "Verbose mode: $VERBOSE" >&2
    print_status "INFO" "Dry run mode: $DRY_RUN" >&2
    echo >&2
    
    # Capture start time for timing calculation
    local start_time=$(date +%s)
    
    # Validate configuration file
    validate_config "$CONFIG_FILE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
                print_status "INFO" "Dry run mode: Would run command: ${command_args[*]}" >&2
    exit 0
    fi
    
    # Create temporary file for command output
    local output_file
    output_file=$(mktemp)
    trap 'rm -f "$output_file"' EXIT
    
    # Run the command and capture its exit code
    local command_exit_code
    run_command "$output_file" "${command_args[@]}"
    command_exit_code=$?
    
    # Handle different exit code scenarios
    if [[ "$command_exit_code" -eq 0 ]]; then
        # Command succeeded with no flaws (PASS)
        local summary="Scan completed successfully with no flaws found"
        local disposition="PASS"
        local reason_code="SUCCESS"
        
        # Generate JSON output
        generate_json_output "$command_exit_code" "$reason_code" "$disposition" "$summary" "$output_file" "$start_time" "" "" ""
        
        # Display complete command output
        print_status "INFO" "Complete command output:" >&2
        echo "----------------------------------------" >&2
        cat "$output_file" >&2
        echo "----------------------------------------" >&2
        
        print_status "INFO" "Command completed successfully with no flaws (PASS)" >&2
        exit 0
    elif [[ "$command_exit_code" -ge 1 && "$command_exit_code" -le 200 ]]; then
        # Command found flaws (FAIL with flaw count)
        local summary="Scan completed with $command_exit_code security flaw(s) found"
        local disposition="FAIL"
        local reason_code="FLAWS_FOUND"
        
        # Generate JSON output
        generate_json_output "$command_exit_code" "$reason_code" "$disposition" "$summary" "$output_file" "$start_time" "" "" ""
        
        # Display complete command output
        print_status "INFO" "Complete command output:" >&2
        echo "----------------------------------------" >&2
        cat "$output_file" >&2
        echo "----------------------------------------" >&2
        
        print_status "INFO" "Command completed with $command_exit_code flaw(s) found (FAIL)" >&2
        exit "$command_exit_code"
    elif [[ "$command_exit_code" -eq 255 ]]; then
        # Command failed with error, analyze patterns
        print_status "INFO" "Command exited with code 255, analyzing output for patterns..." >&2
        
        # Check grep support
        local grep_type
        grep_type=$(check_grep_support)
        if [[ "$VERBOSE" == "true" ]]; then
            print_status "INFO" "Using $grep_type regex support"
        fi
        
                # Process patterns
        local result
        result=$(process_patterns "$CONFIG_FILE" "$output_file" "$grep_type")
        
        
        
        # Determine final exit code
        local final_exit_code=0
        local pattern_name=""
        local pattern_regex=""
        local pattern_count=0
        
        if [[ "$result" == "NO_MATCHES" ]]; then
            final_exit_code=255  # No patterns matched, return 255
            local summary="Command failed but no specific error patterns were identified"
            local disposition="FAIL"
            local reason_code="UNKNOWN_ERROR"
            
            # Generate JSON output
            generate_json_output "$final_exit_code" "$reason_code" "$disposition" "$summary" "$output_file" "$start_time" "" "" ""
            
            # Display complete command output
            print_status "INFO" "Complete command output:" >&2
            echo "----------------------------------------" >&2
            cat "$output_file" >&2
            echo "----------------------------------------" >&2
            
            print_status "INFO" "No patterns matched in command output, returning 255" >&2
        else
            # Parse the JSON-like result string
            if [[ "$result" =~ \"exit_code\":\"([^\"]+)\" ]]; then
                final_exit_code="${BASH_REMATCH[1]}"
            fi
            if [[ "$result" =~ \"pattern_name\":\"([^\"]+)\" ]]; then
                pattern_name="${BASH_REMATCH[1]}"
            fi
            if [[ "$result" =~ \"pattern_regex\":\"([^\"]+)\" ]]; then
                pattern_regex="${BASH_REMATCH[1]}"
            fi
            if [[ "$result" =~ \"pattern_count\":\"([^\"]+)\" ]]; then
                pattern_count="${BASH_REMATCH[1]}"
            fi
            
            local summary="Command failed with identified error pattern (exit code: $final_exit_code)"
            local disposition="FAIL"
            local reason_code="PATTERN_MATCHED"
            
                    # Generate JSON output
        generate_json_output "$final_exit_code" "$reason_code" "$disposition" "$summary" "$output_file" "$start_time" "$pattern_name" "$pattern_regex" "$pattern_count"
        
        print_status "SUCCESS" "Patterns matched - exiting with code: $final_exit_code" >&2
        # Output the logical exit code to stderr for the calling process to capture
        echo "LOGICAL_EXIT_CODE: $final_exit_code" >&2
    fi
    
    # Display complete command output
    print_status "INFO" "Complete command output:" >&2
    echo "----------------------------------------" >&2
    cat "$output_file" >&2
    echo "----------------------------------------" >&2
    
    exit "$final_exit_code"
    else
        # Unexpected exit code
        local summary="Command exited with unexpected code: $command_exit_code"
        local disposition="FAIL"
        local reason_code="UNEXPECTED_EXIT"
        
        # Generate JSON output
        generate_json_output "$command_exit_code" "$reason_code" "$disposition" "$summary" "$output_file" "$start_time" "" "" ""
        
        # Display complete command output
        print_status "INFO" "Complete command output:" >&2
        echo "----------------------------------------" >&2
        cat "$output_file" >&2
        echo "----------------------------------------" >&2
        
        print_status "WARN" "Command exited with unexpected code: $command_exit_code" >&2
        exit "$command_exit_code"
    fi
}

# Run main function with all arguments
main "$@"
