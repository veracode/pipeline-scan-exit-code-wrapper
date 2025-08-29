# Veracode Pipeline-Scan Wrapper

A robust bash script wrapper for Veracode pipeline-scan commands that provides intelligent error analysis, pattern matching, and standardized exit codes for CI/CD integration.

## Overview

The Veracode Pipeline-Scan Wrapper acts as a command wrapper that:
- Executes any command and displays its output in real-time
- Analyzes command output for specific error patterns when the original command exits with code 255
- Provides standardized exit codes (201-254) for different error categories
- Preserves original exit codes (0-200) when no patterns are matched
- Handles complex commands with spaces and special characters correctly

## Features

- **Command Wrapping**: Wraps any command while preserving argument structure
- **Real-time Output**: Displays command output as it runs
- **Pattern Analysis**: Detects specific error patterns in command output
- **Standardized Exit Codes**: Uses category-based exit codes (201-254) for consistent CI/CD integration
- **Space Handling**: Properly handles file paths with spaces and special characters
- **Configurable Patterns**: Easy-to-modify pattern configuration file

## Installation

1. Clone or download the repository
2. Make the script executable:
   ```bash
   chmod +x pipeline-scan-analyzer.sh
   ```
3. Ensure `grep` with extended regex support is available
4. Customize `patterns.conf` if needed

## Usage

### Basic Syntax

```bash
./pipeline-scan-analyzer.sh [OPTIONS] -- COMMAND [ARGS...]
```

### Options

- `-c, --config FILE`: Specify custom patterns configuration file (default: `patterns.conf`)
- `-v, --verbose`: Enable verbose output
- `-d, --dry-run`: Show what would be executed without running the command
- `-h, --help`: Display help information

### Examples

#### Basic Command Wrapping
```bash
# Wrap a simple command
./pipeline-scan-analyzer.sh -- echo "Hello World"

# Wrap a command with file paths containing spaces
./pipeline-scan-analyzer.sh -- java -jar pipeline-scan.jar -f "/path/with spaces/file.war"

# Wrap Veracode pipeline-scan
./pipeline-scan-analyzer.sh -- java -jar pipeline-scan.jar -f "target/app.war"
```

#### With Custom Configuration
```bash
# Use custom patterns file
./pipeline-scan-analyzer.sh -c custom-patterns.conf -- java -jar pipeline-scan.jar -f "app.war"

# Verbose mode
./pipeline-scan-analyzer.sh -v -- java -jar pipeline-scan.jar -f "app.war"
```

## Exit Code Taxonomy

The wrapper uses a standardized exit code system to categorize different types of errors:

### **TIMEOUTS (201-209)**
- `201`: `TIMEOUT_DEFAULT` - Exceeded default 60-minute limit
- `202`: `TIMEOUT_USER` - Exceeded user-specified timeout value

### **AUTH / ORG (210-219)**
- `210`: `AUTH_INVALID_CREDENTIALS` - API ID/key bad or expired, 401 errors
- `211`: `AUTH_INSUFFICIENT_PERMISSIONS` - Token valid but lacks app/scan rights
- `212`: `ACCOUNT_RATE_LIMIT` - Platform throttling, 429 errors

### **NETWORK / TRANSPORT (220-229)**
- `220`: `NET_DNS` - Cannot resolve host, DNS issues
- `221`: `NET_TLS` - SSL/TLS handshake or certificate validation failure
- `222`: `NET_PROXY` - Proxy authentication or connectivity failure

### **CONFIGURATION (CALLER) (230-239)**
- `230`: `CONFIG_INVALID_PARAM` - Bad CLI arguments, mutually exclusive flags
- `231`: `CONFIG_POLICY_REFERENCE_NOT_FOUND` - Named policy/ruleset missing
- `232`: `CONFIG_BASELINE_MISSING` - Baseline file path not found or unreadable
- `233`: `CONFIG_THRESHOLD_CONFLICT` - Conflicting --fail_on_* settings

### **PACKAGING / ARTIFACT (240-249)**
- `240`: `PKG_ARTIFACT_NOT_FOUND` - Built package/path missing, file not found
- `241`: `PKG_TOO_LARGE` - Exceeds size limit
- `242`: `PKG_UNSUPPORTED_LANG` - No supported files detected for scan type
- `243`: `PKG_EXCLUDE_RULES_ELIMINATED_ALL` - Glob/exclude removed all inputs

### **ENGINE / SCAN EXECUTION (250-254)**
- `250`: `ENGINE_PARSER_ERROR` - Preprocessing/AST parse error prevents analysis
- `251`: `ENGINE_RULEPACK_INCOMPATIBLE` - Ruleset version mismatch
- `252`: `ENGINE_PARTIAL_SCAN` - Scan completed with modules skipped (degraded)
- `253`: `ENGINE_SCAN_FAILED` - General scan or analysis failure
- `254`: `ENGINE_UNKNOWN_ERROR` - Unknown or unexpected engine error

### **Original Exit Codes (0-200)**
- `0`: Success (PASS: no flaws found under current thresholds)
- `1-200`: FAIL: flaws found; value equals flaw count

## Pattern Configuration

Patterns are defined in `patterns.conf` using the format:
```
CATEGORY_NAME|pattern_regex|exit_code
```

### Example Patterns
```
AUTH_INVALID_CREDENTIALS|401|210
AUTH_INVALID_CREDENTIALS|unauthorized|210
PKG_ARTIFACT_NOT_FOUND|file not found|240
ENGINE_PARSER_ERROR|parse error|250
```

## How It Works

1. **Command Execution**: The wrapper executes the provided command and captures its output
2. **Exit Code Analysis**: 
   - If original exit code is 0-200: preserved (flaw count or success)
   - If original exit code is 255: triggers pattern analysis
3. **Pattern Matching**: Searches command output for configured patterns
4. **Exit Code Determination**: 
   - Uses original exit code if no patterns match
   - Uses logical exit code from pattern matching if patterns are found
5. **Output Display**: Shows command output, analysis summary, and final exit code

## CI/CD Integration

The wrapper is designed for seamless CI/CD integration:

```yaml
# GitHub Actions Example
- name: Run Veracode Scan
  run: |
    ./pipeline-scan-analyzer.sh -- java -jar pipeline-scan.jar -f "target/app.war"
  
- name: Handle Scan Results
  run: |
    case $? in
      0) echo "Scan passed - no flaws found" ;;
      1-200) echo "Scan failed - found $? flaws" ;;
      201-254) echo "Scan failed - error category: $?" ;;
    esac
```

```yaml
# GitLab CI Example
veracode_scan:
  script:
    - ./pipeline-scan-analyzer.sh -- java -jar pipeline-scan.jar -f "target/app.war"
  after_script:
    - |
      case $? in
        0) echo "Scan passed - no flaws found" ;;
        1-200) echo "Scan failed - found $? flaws" ;;
        201-254) echo "Scan failed - error category: $?" ;;
      esac
```

## Requirements

- **Bash**: Version 4.0 or higher
- **grep**: With extended regex support (`grep -E`)
- **Unix-like environment**: Linux, macOS, or WSL

## Troubleshooting

### Common Issues

1. **"grep with extended regex support (-E) is required"**
   - Ensure `grep -E` is available and functional
   - Test with: `echo "test" | grep -E "test"`

2. **Command arguments with spaces not working**
   - Use quotes around arguments: `"/path/with spaces/file.war"`
   - The wrapper automatically handles proper quoting

3. **Patterns not matching**
   - Check regex syntax in `patterns.conf`
   - Use verbose mode (`-v`) to see detailed output
   - Ensure patterns are specific enough to avoid false positives

### Debug Mode

Enable verbose output to troubleshoot issues:
```bash
./pipeline-scan-analyzer.sh -v -- your-command
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review the pattern configuration
3. Enable verbose mode for debugging
4. Open an issue with detailed error information