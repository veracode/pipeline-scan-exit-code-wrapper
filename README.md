# Veracode Pipeline-Scan Wrapper

A bash script that acts as a wrapper around Veracode pipeline-scan (or any command), running it and analyzing the output for specific patterns when the command exits with code 255. The script implements the official Veracode exit code taxonomy to provide granular error classification for CI/CD pipeline integration. After analysis, it displays the complete command output for easy review.

## Features

- **Command Wrapper**: Runs any command and displays output in real-time
- **Pattern Analysis**: Analyzes command output only when exit code is 255
- **Official Exit Code Taxonomy**: Implements Veracode's negative exit code system
- **Preserves Original Exit Codes**: Keeps 0 (PASS) and 1-200 (FAIL with flaw count)
- **Configurable Patterns**: Define custom regex patterns in a simple configuration file
- **Verbose Output**: Optional detailed logging for debugging and monitoring
- **Dry Run Mode**: Test your configuration without actually running commands
- **Cross-Platform**: Works with different grep implementations (Perl, Extended, Basic regex)

## Files

- `pipeline-scan-analyzer.sh` - Main wrapper script
- `patterns.conf` - Configuration file with patterns and exit codes
- `README.md` - This documentation file

## Installation

1. Make the script executable:
   ```bash
   chmod +x pipeline-scan-analyzer.sh
   ```

2. Ensure you have bash and grep available (standard on most Unix-like systems)

## Configuration

The `patterns.conf` file uses a simple pipe-separated format:

```
PATTERN_NAME|REGEX_PATTERN|EXIT_CODE
```

### Exit Code Taxonomy

The script implements the official Veracode Pipeline-Scan exit code taxonomy using negative values to avoid colliding with the flaw-count range (1-200):

#### Timeouts
- **-10**: TIMEOUT_DEFAULT - exceeded default 60-min limit
- **-11**: TIMEOUT_USER - exceeded --timeout value

#### Auth/Org
- **-20**: AUTH_INVALID_CREDENTIALS - API ID/key bad or expired
- **-21**: AUTH_INSUFFICIENT_PERMISSIONS - token valid but lacks rights
- **-22**: ACCOUNT_RATE_LIMIT - platform throttling/429

#### Network/Transport
- **-30**: NET_DNS - cannot resolve host
- **-31**: NET_TLS - SSL/TLS handshake/cert validation failure
- **-32**: NET_PROXY - proxy auth/connectivity failure

#### Configuration
- **-40**: CONFIG_INVALID_PARAM - bad CLI arg
- **-41**: CONFIG_POLICY_REFERENCE_NOT_FOUND - named policy missing
- **-42**: CONFIG_BASELINE_MISSING - baseline file not found
- **-43**: CONFIG_THRESHOLD_CONFLICT - conflicting settings

#### Packaging/Artifact
- **-50**: PKG_ARTIFACT_NOT_FOUND - built package/path missing
- **-51**: PKG_TOO_LARGE - exceeds size limit
- **-52**: PKG_UNSUPPORTED_LANG - no supported files detected
- **-53**: PKG_EXCLUDE_RULES_ELIMINATED_ALL - glob/exclude removed all

#### Engine/Scan Execution
- **-60**: ENGINE_PARSER_ERROR - preprocessing/AST parse error
- **-61**: ENGINE_RULEPACK_INCOMPATIBLE - ruleset version mismatch
- **-62**: ENGINE_PARTIAL_SCAN - scan completed with modules skipped

#### Results/Post-processing
- **-70**: RESULT_UPLOAD_FAILED - results couldn't be posted to API
- **-71**: RESULT_WRITE_FAILED - couldn't write results artifact
- **-72**: RESULT_FORMAT_ERROR - SARIF/JSON transform failed

## Usage

### Basic Usage

```bash
./pipeline-scan-analyzer.sh -- veracode-pipeline-scan --file app.zip
```

### With Custom Configuration

```bash
./pipeline-scan-analyzer.sh -c custom_patterns.conf -- veracode-pipeline-scan --verbose --file app.zip
```

### Verbose Mode

```bash
./pipeline-scan-analyzer.sh -v -- veracode-pipeline-scan --file app.zip
```

### Dry Run (Test Mode)

```bash
./pipeline-scan-analyzer.sh --dry-run -- echo "test command"
```

### Help

```bash
./pipeline-scan-analyzer.sh --help
```

## Command Line Options

| Option | Long Option | Description |
|--------|-------------|-------------|
| `-c` | `--config` | Specify custom configuration file (default: `patterns.conf`) |
| `-v` | `--verbose` | Enable verbose output |
| `-d` | `--dry-run` | Show what would be done without running the command |
| `-j` | `--json` | Output results to JSON file |
| `-h` | `--help` | Show help message |

## Exit Codes

### Standard Veracode Exit Codes
- **0**: PASS - no flaws found (under current thresholds)
- **1-200**: FAIL - flaws found; value = count
- **255**: Command failed but no patterns matched

### Granular Error Codes (Converted to Positive by Bash)
When the wrapped command exits with code 255, the script analyzes patterns and returns specific error codes. Since bash only supports exit codes 0-255, negative codes are converted by adding 256:

| Logical Code | Bash Code | Category | Description |
|--------------|-----------|----------|-------------|
| -10 | 246 | Timeout | Default 60-min limit exceeded |
| -11 | 245 | Timeout | User-specified timeout exceeded |
| -20 | 236 | Auth | Invalid API credentials |
| -21 | 235 | Auth | Insufficient permissions |
| -22 | 234 | Auth | Rate limit exceeded |
| -30 | 226 | Network | DNS resolution failure |
| -31 | 225 | Network | TLS/SSL handshake failure |
| -32 | 224 | Network | Proxy connectivity failure |
| -40 | 216 | Config | Invalid CLI parameter |
| -41 | 215 | Config | Policy reference not found |
| -42 | 214 | Config | Baseline missing |
| -43 | 213 | Config | Threshold conflict |
| -50 | 206 | Package | Artifact not found |
| -51 | 205 | Package | Package too large |
| -52 | 204 | Package | Unsupported language |
| -53 | 203 | Package | Exclude rules eliminated all files |
| -60 | 196 | Engine | Parser error |
| -61 | 195 | Engine | Rulepack incompatible |
| -62 | 194 | Engine | Partial scan |
| -70 | 186 | Results | Upload failed |
| -71 | 185 | Results | Write failed |
| -72 | 184 | Results | Format error |

### System Exit Codes (100+)
- **100**: Configuration file not found
- **101**: Invalid command format

## Examples

### CI/CD Pipeline Integration

#### GitHub Actions

```yaml
- name: Run Veracode Pipeline Scan with Wrapper
  run: |
    ./pipeline-scan-analyzer.sh -- veracode-pipeline-scan --file app.zip
  continue-on-error: true
  id: veracode_scan

- name: Handle Authentication Issues
  if: steps.veracode_scan.outcome == 'failure' && steps.veracode_scan.outputs.exit-code == '236'
  run: |
    echo "Authentication failed (exit 236 = -20) - check API credentials"
    
- name: Handle Package Issues  
  if: steps.veracode_scan.outcome == 'failure' && steps.veracode_scan.outputs.exit-code >= '203' && steps.veracode_scan.outputs.exit-code <= '206'
  run: |
    echo "Package/artifact issue detected"
    
- name: Handle Security Findings
  if: steps.veracode_scan.outcome == 'failure' && steps.veracode_scan.outputs.exit-code >= '1' && steps.veracode_scan.outputs.exit-code <= '200'
  run: |
    echo "Security findings detected: ${{ steps.veracode_scan.outputs.exit-code }} flaw(s)"
```

#### Jenkins Pipeline

```groovy
pipeline {
    agent any
    stages {
        stage('Veracode Scan') {
            steps {
                script {
                    def exitCode = sh(
                        script: './pipeline-scan-analyzer.sh -- veracode-pipeline-scan --file app.zip',
                        returnStatus: true
                    )
                    
                    if (exitCode == 0) {
                        echo "Scan passed - no flaws found"
                    } else if (exitCode >= 1 && exitCode <= 200) {
                        echo "Security findings detected: ${exitCode} flaw(s)"
                        currentBuild.result = 'UNSTABLE'
                    } else if (exitCode == 236) {  // -20
                        error "Authentication failed - check API credentials"
                    } else if (exitCode >= 203 && exitCode <= 206) {  // -53 to -50
                        error "Package/artifact issue detected"
                    } else if (exitCode >= 224 && exitCode <= 226) {  // -32 to -30
                        error "Network issue detected"
                    } else if (exitCode == 255) {
                        error "Scan failed but no specific pattern matched"
                    } else {
                        error "Unexpected exit code: ${exitCode}"
                    }
                }
            }
        }
    }
}
```

### Custom Pattern Configuration

```bash
# Create custom patterns for your specific needs
cat > custom_patterns.conf << EOF
# Custom authentication patterns
CUSTOM_AUTH_ERROR|authentication.*failed|-20
CUSTOM_AUTH_ERROR|login.*denied|-20

# Custom package patterns  
CUSTOM_PKG_ERROR|package.*corrupted|-50
CUSTOM_PKG_ERROR|invalid.*format|-50

# Custom network patterns
CUSTOM_NET_ERROR|connection.*timeout|-30
CUSTOM_NET_ERROR|server.*unreachable|-30
EOF

# Use with custom config
./pipeline-scan-analyzer.sh -c custom_patterns.conf -- your-scan-command
```

## JSON Output

The script automatically generates a comprehensive JSON report named `veracode-pipeline-scan-wrapper.json` for programmatic analysis and CI/CD integration:

```bash
./pipeline-scan-analyzer.sh -- your-command
# JSON file automatically created: veracode-pipeline-scan-wrapper.json
```

### JSON Output Format

The JSON output follows this structure:

```json
{
    "tool": "veracode-pipeline-scan",
    "version": "wrapper-1.0",
    "disposition": "PASS|FAIL",
    "exit_code": 0,
    "reason_code": "SUCCESS|FLAWS_FOUND|PATTERN_MATCHED|UNKNOWN_ERROR|UNEXPECTED_EXIT",
    "summary": "Human-readable description",
    "flaw_count": 0,
    "severity_counts": {"very_high": 0, "high": 0, "medium": 0, "low": 0, "info": 0},
    "timing": {
        "total_ms": 1500
    },
    "context": {
        "event": "push|pull_request|manual|unknown",
        "repo": "owner/repo|group/project|unknown",
        "commit": "sha|unknown",
        "branch": "main|feature|unknown"
    },
    "pattern_match": {
        "name": "Pattern name from config",
        "regex": "Regex pattern that matched",
        "count": 1
    },
    "raw": {
        "stdout_tail": ["Last 20 lines of command output"],
        "stderr_tail": ["Last 20 lines of stderr"]
    }
}
```

### JSON Field Descriptions

- **tool**: Always "veracode-pipeline-scan"
- **version**: Wrapper version (currently "wrapper-1.0")
- **disposition**: Overall result - "PASS" or "FAIL"
- **exit_code**: The actual exit code returned by the script
- **reason_code**: Specific reason for the result
  - `SUCCESS`: Command completed successfully (exit 0)
  - `FLAWS_FOUND`: Security flaws detected (exit 1-200)
  - `PATTERN_MATCHED`: Error pattern identified (exit -10 to -79)
  - `UNKNOWN_ERROR`: No patterns matched (exit 255)
  - `UNEXPECTED_EXIT`: Unexpected exit code
- **summary**: Human-readable description of the result
- **flaw_count**: Number of security flaws found (0 for non-scan failures)
- **severity_counts**: Breakdown of flaws by severity (automatically parsed from command output)
  - `very_high`: Count of Very High severity issues
  - `high`: Count of High severity issues  
  - `medium`: Count of Medium severity issues
  - `low`: Count of Low severity issues
  - `info`: Count of Informational severity issues
- **timing**: Execution time in milliseconds
- **context**: CI/CD environment information (GitHub Actions, GitLab CI, etc.)
- **pattern_match**: Pattern matching details (only present when `reason_code` is `PATTERN_MATCHED`)
  - `name`: Name of the matched pattern from configuration
  - `regex`: The regex pattern that matched
  - `count`: Number of times the pattern was found
- **raw**: Last 20 lines of command output for debugging

**Note**: The `pattern_match` section is only included in the JSON when a pattern is actually matched (i.e., when `reason_code` is `PATTERN_MATCHED`). For all other scenarios, this section is omitted.

### Severity Count Parsing

When the command exits with a flaw count (exit codes 1-200), the script automatically parses the command output to extract severity information. It looks for patterns like:

```
Found 4 issues of Very High severity.
Found 14 issues of High severity.
Found 117 issues of Medium severity.
Found 30 issues of Low severity.
Found 18 issues of Informational severity.
```

The severity counts are then included in the JSON output for detailed analysis and reporting.

### CI/CD Integration with JSON

```bash
# Run the wrapper - JSON file automatically generated
./pipeline-scan-analyzer.sh -- veracode-pipeline-scan --file app.zip

# Parse results in your CI/CD script
if [ -f "veracode-pipeline-scan-wrapper.json" ]; then
    disposition=$(jq -r '.disposition' veracode-pipeline-scan-wrapper.json)
    exit_code=$(jq -r '.exit_code' veracode-pipeline-scan-wrapper.json)
    reason_code=$(jq -r '.reason_code' veracode-pipeline-scan-wrapper.json)
    
    echo "Scan disposition: $disposition"
    echo "Exit code: $exit_code"
    echo "Reason: $reason_code"
    
    if [ "$disposition" = "FAIL" ]; then
        if [ "$exit_code" -ge 1 ] && [ "$exit_code" -le 200 ]; then
            echo "Security flaws detected: $exit_code"
        elif [ "$exit_code" -eq 236 ]; then  # -20
            echo "Authentication failed - check credentials"
        elif [ "$exit_code" -eq 255 ]; then
            echo "Unknown error occurred"
        fi
    fi
fi
```

## Troubleshooting

### Common Issues

1. **Permission Denied**: Make sure the script is executable (`chmod +x pipeline-scan-analyzer.sh`)

2. **Configuration File Not Found**: Check the path to your `patterns.conf` file

3. **Pattern Not Matching**: Use verbose mode (`-v`) to see which patterns are being processed

4. **Command Parsing Issues**: Make sure to use `--` before your command arguments

### Debug Mode

Use the `--dry-run` flag to test your configuration without running the actual command:

```bash
./pipeline-scan-analyzer.sh --dry-run --verbose -- veracode-pipeline-scan --file app.zip
```

### Testing Patterns

You can test individual patterns using grep on command output:

```bash
# Capture command output to a file
your-command > output.txt 2>&1

# Test a pattern from your config
grep -E "credentials.*invalid" output.txt
```

### Understanding Exit Code Conversion

Remember that bash converts negative exit codes to positive values:
- Logical exit code: -20 (AUTH_INVALID_CREDENTIALS)  
- Actual bash exit code: 236 (256 + (-20))

You can convert back to logical codes in your scripts:
```bash
if [ $exit_code -gt 200 ]; then
    logical_code=$((exit_code - 256))
    echo "Logical exit code: $logical_code"
fi
```

## How It Works

1. **Command Execution**: The wrapper runs your command and displays output in real-time
2. **Exit Code Preservation**: Commands exiting with 0 or 1-200 pass through unchanged
3. **Pattern Analysis**: Only when exit code is 255, the wrapper:
   - Analyzes the captured command output
   - Searches for configured patterns using regex
   - Returns the most specific negative exit code found
   - If no patterns match, returns 255
4. **Complete Output Display**: After analysis, the wrapper displays the complete command output for review

This design ensures that normal Veracode scan results (pass/fail with flaw counts) are preserved while providing detailed error classification for actual scan failures.

## Contributing

Feel free to submit issues, feature requests, or pull requests to improve this tool.

## License

This project is open source and available under the MIT License.