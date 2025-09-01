#!/bin/bash

# Veracode Pipeline-Scan Wrapper Script
# This script wraps any command and analyzes its output for specific patterns,
# then exits with a logical exit code based on the patterns found.

set -eo pipefail

# Configuration
CONFIG_FILE="patterns.conf"
VERBOSE="false"
DRY_RUN="false"
JSON_OUTPUT="veracode-pipeline-scan-wrapper.json"

# Global variable for output file
OUTPUT_FILE=""

# Function to print status messages
print_status() {
    local level="$1"
    local message="$2"
    echo "[WRAPPER] $level: $message" >&2
}

# Function to display usage information
usage() {
    cat >&2 << EOF
Usage: $0 [OPTIONS] -- <command>

Options:
    -c, --config FILE    Configuration file (default: patterns.conf)
    -v, --verbose        Enable verbose output
    -d, --dry-run        Show what would be done without executing
    -h, --help           Show this help message

The script will:
1. Execute the provided command and display its output in real-time
2. Always analyze the command output for patterns from the config file
3. Exit with a logical exit code based on patterns found:
   - 0: No patterns matched (PASS)
   - 201-209: Timeout issues
   - 210-219: Auth/Org issues  
   - 220-229: Network/Transport issues
   - 230-239: Configuration issues
   - 240-249: Packaging/Artifact issues
   - 250-259: Engine/Scan execution issues
   - 260-269: Results/Post-processing issues

Examples:
    $0 -- veracode pipeline-scan
    $0 -c custom.conf -- veracode pipeline-scan --fail-on-high
    $0 -v -- veracode pipeline-scan --timeout 120

EOF
}

# Function to validate configuration file
validate_config() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        print_status "ERROR" "Configuration file '$config_file' not found"
        exit 1
    fi
    
    if [[ ! -r "$config_file" ]]; then
        print_status "ERROR" "Configuration file '$config_file' is not readable"
        exit 1
    fi
    
    # Check if file has content
    if [[ ! -s "$config_file" ]]; then
        print_status "ERROR" "Configuration file '$config_file' is empty"
        exit 1
    fi
    
    print_status "INFO" "Configuration file '$config_file' validated"
}

# Function to check grep support for extended regex
check_grep_support() {
    # Test if grep -E works by trying to use it
    if ! echo "test" | grep -E "test" >/dev/null 2>&1; then
        print_status "ERROR" "grep with extended regex support (-E) is required"
        exit 1
    fi
}

# Function to process patterns and find matches
process_patterns() {
    local output_file="$1"
    local config_file="$2"
    
    local matched_patterns=()
    local highest_exit_code=0
    
    # Read patterns from config file
    while IFS='|' read -r pattern_name pattern_regex exit_code; do
        # Skip comments and empty lines
        [[ "$pattern_name" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$pattern_name" ]] && continue
        
        # Remove leading/trailing whitespace
        pattern_name=$(echo "$pattern_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        pattern_regex=$(echo "$pattern_regex" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        exit_code=$(echo "$exit_code" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Skip if any field is empty or contains only whitespace
        [[ -z "$pattern_name" || -z "$pattern_regex" || -z "$exit_code" ]] && continue
        
        # Validate exit code is numeric
        [[ ! "$exit_code" =~ ^[0-9]+$ ]] && continue
        
        # Check if pattern matches in output
        local match_count=0
        match_count=$(grep -c -E "$pattern_regex" "$output_file" 2>/dev/null | tr -d '\n' || echo "0")
        
        # Debug: Print variables to see what's causing the issue
        if [[ "$VERBOSE" == "true" ]]; then
            print_status "DEBUG" "Processing pattern: '$pattern_name' | '$pattern_regex' | '$exit_code'" >&2
            print_status "DEBUG" "Match count: '$match_count' (length: ${#match_count})" >&2
            print_status "DEBUG" "Match count hex: $(echo -n "$match_count" | hexdump -C)" >&2
        fi
        
        if [[ "$match_count" -gt 0 ]]; then
            matched_patterns+=("$pattern_name|$pattern_regex|$exit_code|$match_count")
            
            # Update highest exit code (we want the highest positive number)
            if [[ "$exit_code" -gt "$highest_exit_code" ]]; then
                highest_exit_code="$exit_code"
            fi
        fi
    done < "$config_file"
    
    # Return results as JSON-like string
    if [[ ${#matched_patterns[@]} -gt 0 ]]; then
        local first_match="${matched_patterns[0]}"
        IFS='|' read -r pattern_name pattern_regex exit_code match_count <<< "$first_match"
        echo "{\"exit_code\": $exit_code, \"pattern_name\": \"$pattern_name\", \"pattern_regex\": \"$pattern_regex\", \"pattern_count\": $match_count}"
    else
        echo "{\"exit_code\": 0, \"pattern_name\": \"\", \"pattern_regex\": \"\", \"pattern_count\": 0}"
    fi
}

# Function to run the wrapped command
run_command() {
    local command_args=("$@")
    
    # Create temporary file for command output
    OUTPUT_FILE=$(mktemp)
    
    # Clean up temp file on exit
    trap 'rm -f "$OUTPUT_FILE" "$OUTPUT_FILE.exit"' EXIT
    
    # Display the command as it will be executed (preserving quotes)
    # We need to reconstruct the original command string with proper quoting
    local cmd_display=""
    for arg in "${command_args[@]}"; do
        # Always quote arguments that contain spaces, special chars, or are empty
        if [[ "$arg" =~ [[:space:]] || "$arg" =~ [\"\'\\\|\&\;\(\)\<\>\$\`] || -z "$arg" ]]; then
            # Escape any existing quotes and wrap in double quotes
            local escaped_arg="${arg//\"/\\\"}"
            cmd_display="$cmd_display \"$escaped_arg\""
        else
            cmd_display="$cmd_display $arg"
        fi
    done
    cmd_display="${cmd_display# }"  # Remove leading space
    
    print_status "INFO" "Running command: $cmd_display"
    echo "----------------------------------------" >&2
    print_status "INFO" "Executing command: $cmd_display" >&2
    
    # Execute command and capture output
    local result
    local exit_code
    
    # Execute the command directly without eval to preserve argument structure
    if result=$("${command_args[@]}" 2>&1 | tee "$OUTPUT_FILE"); then
        # Command succeeded
        exit_code=0
    else
        # Command failed, but we still have output to analyze
        exit_code=${PIPESTATUS[0]}
    fi
    
    print_status "INFO" "Command execution completed with exit code: $exit_code" >&2
    echo "----------------------------------------" >&2
    echo "$result"
    echo "$exit_code" > "$OUTPUT_FILE.exit"
}

# Function to display summary information
display_summary() {
    local original_exit_code="$1"
    local pattern_result="$2"
    local output_file="$3"
    
    echo "" >&2
    echo "----------------------------------------" >&2
    print_status "INFO" "ANALYSIS SUMMARY" >&2
    echo "----------------------------------------" >&2
    
    # Parse pattern result
    local pattern_name=""
    local pattern_regex=""
    local pattern_count=0
    local logical_exit_code=0
    
    if [[ -n "$pattern_result" ]]; then
        # Extract values from JSON-like string
        pattern_name=$(echo "$pattern_result" | grep -o '"pattern_name": "[^"]*"' | cut -d'"' -f4)
        pattern_regex=$(echo "$pattern_result" | grep -o '"pattern_regex": "[^"]*"' | cut -d'"' -f4)
        pattern_count=$(echo "$pattern_result" | grep -o '"pattern_count": [0-9]*' | cut -d' ' -f2)
        logical_exit_code=$(echo "$pattern_result" | grep -o '"exit_code": [0-9]*' | cut -d' ' -f2)
    fi
    
    # Display summary
    echo "Original command exit code: $original_exit_code" >&2
    
    if [[ -n "$pattern_name" && "$logical_exit_code" -gt 0 ]]; then
        echo "Pattern matched: $pattern_name" >&2
        echo "Pattern regex: $pattern_regex" >&2
        echo "Match count: $pattern_count" >&2
        echo "Logical exit code: $logical_exit_code" >&2
        echo "Reason: Pattern '$pattern_name' found in command output" >&2
    else
        echo "Pattern matched: None" >&2
        echo "Logical exit code: 0" >&2
        echo "Reason: No patterns matched in command output" >&2
    fi
    
    echo "----------------------------------------" >&2
}

# Main function
main() {
    local command_args=()
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --)
                shift
                # Capture all remaining arguments as a single command string
                # This preserves the original quoting and spacing
                command_args=("$@")
                break
                ;;
            *)
                echo "Unknown option: $1" >&2
                usage
                exit 1
                ;;
        esac
    done
    
    # Check if command was provided
    if [[ ${#command_args[@]} -eq 0 ]]; then
        print_status "ERROR" "No command provided. Use -- to separate options from command."
        usage
        exit 1
    fi
    
    # Display startup information
    print_status "INFO" "Starting Veracode Pipeline-Scan Wrapper..."
    print_status "INFO" "Configuration file: $CONFIG_FILE"
    
    # Display the command with proper quoting
    local cmd_display_startup=""
    for arg in "${command_args[@]}"; do
        if [[ "$arg" =~ [[:space:]] ]]; then
            cmd_display_startup="$cmd_display_startup \"$arg\""
        else
            cmd_display_startup="$cmd_display_startup $arg"
        fi
    done
    cmd_display_startup="${cmd_display_startup# }"  # Remove leading space
    
    print_status "INFO" "Command: $cmd_display_startup"
    print_status "INFO" "Verbose mode: $VERBOSE"
    print_status "INFO" "Dry run mode: $DRY_RUN"
    echo "" >&2
    
    # Validate configuration
    validate_config "$CONFIG_FILE"
    
    # Check grep support
    check_grep_support
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "INFO" "DRY RUN: Would execute: ${command_args[*]}"
        exit 0
    fi
    
    # Run the command
    run_command "${command_args[@]}"
    
    # Get the original exit code
    local original_exit_code
    original_exit_code=$(cat "$OUTPUT_FILE.exit" 2>/dev/null || echo "0")
    
    # Always analyze patterns (regardless of exit code)
    print_status "INFO" "Analyzing command output for patterns..." >&2
    if [[ "$VERBOSE" == "true" ]]; then
        print_status "DEBUG" "Output file: $OUTPUT_FILE" >&2
        print_status "DEBUG" "Output file contents:" >&2
        cat "$OUTPUT_FILE" >&2
        print_status "DEBUG" "End of output file" >&2
    fi
    
    local pattern_result
    pattern_result=$(process_patterns "$OUTPUT_FILE" "$CONFIG_FILE")
    if [[ "$VERBOSE" == "true" ]]; then
        print_status "DEBUG" "Pattern result: $pattern_result" >&2
    fi
    
    # Display summary
    display_summary "$original_exit_code" "$pattern_result" "$OUTPUT_FILE"
    
    # Determine final exit code
    local final_exit_code="$original_exit_code"  # Default to original exit code
    
    # Only override if a pattern was found
    if [[ -n "$pattern_result" ]]; then
        local pattern_exit_code
        pattern_exit_code=$(echo "$pattern_result" | grep -o '"exit_code": [0-9]*' | cut -d' ' -f2)
        
        # Only use pattern exit code if it's not 0 (no pattern matched)
        if [[ "$pattern_exit_code" -gt 0 ]]; then
            final_exit_code="$pattern_exit_code"
            print_status "INFO" "Pattern found - overriding original exit code $original_exit_code with logical exit code: $final_exit_code" >&2
        else
            print_status "INFO" "No patterns matched - using original exit code: $final_exit_code" >&2
        fi
    else
        print_status "INFO" "No patterns matched - using original exit code: $final_exit_code" >&2
    fi
    
    # Exit with final exit code
    print_status "INFO" "Exiting with exit code: $final_exit_code" >&2
    exit "$final_exit_code"
}

# Run main function with all arguments
main "$@"
