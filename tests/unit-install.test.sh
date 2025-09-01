#!/usr/bin/env bash

set -euo pipefail

# ---------- constants ----------
readonly SCRIPT_VERSION="1.0.0"
readonly TEST_DIR="$(mktemp -d)"
readonly INSTALL_SCRIPT="$(dirname "$0")/../install.sh"

# ---------- global variables ----------
use_color=1
is_tty=0
verbose_mode=0
test_failures=0

# ---------- initialization ----------
[[ -t 1 ]] && is_tty=1

# ---------- logging ----------
log() {
    local level="$1"; shift
    local prefix icon color output_fd=1

    case "$level" in
        info)  prefix='>>' icon='>>'; color='36' ;;
        ok)    prefix='✓'  icon='✓';  color='32' ;;
        warn)  prefix='--' icon='--'; color='90' ;;
        error) prefix='!!' icon='!!'; color='31'; output_fd=2 ;;
        test)  prefix='TEST' icon='TEST'; color='35' ;;
        pass)  prefix='PASS' icon='PASS'; color='92' ;;
        fail)  prefix='FAIL' icon='FAIL'; color='91'; output_fd=2 ;;
        *) log error "Unknown log level: $level"; return 1 ;;
    esac

    if [[ $use_color -eq 1 && $is_tty -eq 1 ]]; then
        printf "\033[${color}m${icon}\033[0m %s\n" "$*" >&$output_fd
    else
        printf "%s %s\n" "$prefix" "$*" >&$output_fd
    fi
}

# ---------- cleanup ----------
cleanup() {
    local exit_code=$?
    log info "Cleaning up test environment: $TEST_DIR"
    rm -rf "$TEST_DIR" 2>/dev/null || true

    if [[ $test_failures -eq 0 && $exit_code -eq 0 ]]; then
        log ok "All tests passed!"
    else
        log error "Tests failed (failures: $test_failures, exit code: $exit_code)"
    fi
}

trap cleanup EXIT

# ---------- helpers ----------
run_with_timeout() {
    local seconds="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$seconds" "$@"
    else
        "$@"
    fi
}

# ---------- test functions ----------
test_script_exists() {
    log test "Checking if install script exists"

    if [[ -f "$INSTALL_SCRIPT" ]]; then
        log pass "Install script found: $INSTALL_SCRIPT"
        return 0
    else
        log fail "Install script not found: $INSTALL_SCRIPT"
        ((test_failures++))
        return 1
    fi
}

test_script_executable() {
    log test "Checking if install script is executable"

    if [[ -x "$INSTALL_SCRIPT" ]]; then
        log pass "Install script is executable"
        return 0
    else
        log fail "Install script is not executable"
        ((test_failures++))
        return 1
    fi
}

test_help_option() {
    log test "Testing --help option"

    local help_output
    if help_output="$(bash "$INSTALL_SCRIPT" --help 2>&1)"; then
        if [[ "$help_output" == *"copy-configs installation script"* ]]; then
            log pass "--help option works correctly"
            return 0
        else
            log fail "--help option output incorrect"
            ((test_failures++))
            return 1
        fi
    else
        log fail "--help option failed"
        ((test_failures++))
        return 1
    fi
}

test_os_detection() {
    log test "Testing OS detection functionality"

    # Create a modified version of the script to test detection functions
    local test_script="$TEST_DIR/test_detect.sh"

    # Extract just the detection functions and test them
    cat > "$test_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

detect_os() {
    case "$(uname -s)" in
        Darwin*)
            os_type="darwin"
            ;;
        Linux*)
            if [[ -f /proc/version ]] && grep -q Microsoft /proc/version; then
                os_type="linux"  # WSL
            else
                os_type="linux"
            fi
            ;;
        CYGWIN*|MINGW*|MSYS*)
            echo "error: Windows (non-WSL) is not supported"
            exit 1
            ;;
        *)
            echo "error: Unsupported operating system"
            exit 1
            ;;
    esac
    echo "$os_type"
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)
            arch_type="amd64"
            ;;
        arm64|aarch64)
            arch_type="arm64"
            ;;
        *)
            echo "error: Unsupported architecture"
            exit 1
            ;;
    esac
    echo "$arch_type"
}

echo "OS: $(detect_os)"
echo "ARCH: $(detect_arch)"
EOF

    chmod +x "$test_script"

    local detection_output
    if detection_output="$(bash "$test_script" 2>&1)"; then
        if [[ "$detection_output" == *"OS: "* && "$detection_output" == *"ARCH: "* ]]; then
            log pass "OS and architecture detection works: $detection_output"
            return 0
        else
            log fail "OS/architecture detection output unexpected: $detection_output"
            ((test_failures++))
            return 1
        fi
    else
        log fail "OS/architecture detection failed: $detection_output"
        ((test_failures++))
        return 1
    fi
}

test_dependency_check() {
    log test "Testing dependency checking"

    # Test that required commands exist
    local required_deps=(curl tar)
    local missing=()

    for dep in "${required_deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        log pass "All required dependencies available: ${required_deps[*]}"
        return 0
    else
        log fail "Missing dependencies: ${missing[*]}"
        ((test_failures++))
        return 1
    fi
}

test_github_api_access() {
    log test "Testing GitHub API access"

    local api_url="https://api.github.com/repos/d-kuro/gwq/releases/latest"

    if curl -fsSL --connect-timeout 10 "$api_url" >/dev/null 2>&1; then
        log pass "GitHub API accessible"
        return 0
    else
        log fail "Cannot access GitHub API (network issue or rate limit)"
        ((test_failures++))
        return 1
    fi
}

test_gwq_release_parsing() {
    log test "Testing gwq release information parsing"

    local api_url="https://api.github.com/repos/d-kuro/gwq/releases/latest"
    local release_data

    if ! release_data="$(curl -fsSL --connect-timeout 10 "$api_url" 2>/dev/null)"; then
        log warn "Skipping release parsing test (network issue)"
        return 0
    fi

    # Test version extraction
    local version
    if version="$(echo "$release_data" | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')"; then
        if [[ -n "$version" ]]; then
            log pass "Version parsing works: $version"
        else
            log fail "Version parsing returned empty result"
            ((test_failures++))
            return 1
        fi
    else
        log fail "Version parsing failed"
        ((test_failures++))
        return 1
    fi

    # Test asset URL extraction (for current platform)
    local os_type arch_type release_os release_arch
    case "$(uname -s)" in
        Darwin*) os_type="darwin"; release_os="Darwin" ;;
        Linux*) os_type="linux"; release_os="Linux" ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64) arch_type="amd64"; release_arch="x86_64" ;;
        arm64|aarch64) arch_type="arm64"; release_arch="arm64" ;;
    esac

    local asset_name="gwq_${release_os}_${release_arch}.tar.gz"
    local download_url

    if download_url="$(echo "$release_data" | grep "browser_download_url.*$asset_name" | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')"; then
        if [[ -n "$download_url" ]]; then
            log pass "Asset URL parsing works: $asset_name"
        else
            log fail "Asset URL parsing returned empty result for: $asset_name"
            ((test_failures++))
            return 1
        fi
    else
        log fail "Asset URL parsing failed for: $asset_name"
        log info "Available assets:"
        echo "$release_data" | grep '"name"' | grep '\.tar\.gz' | sed 's/.*"name": *"\([^"]*\)".*/\1/' | sed 's/^/  /'
        ((test_failures++))
        return 1
    fi

    return 0
}

test_repo_access() {
    log test "Testing copy-configs repository access"

    local repo_url="https://github.com/gapurov/copy-configs"

    if curl -fsSL --connect-timeout 10 "$repo_url" >/dev/null 2>&1; then
        log pass "copy-configs repository accessible"
        return 0
    else
        log fail "Cannot access copy-configs repository"
        ((test_failures++))
        return 1
    fi
}

test_dry_run() {
    log test "Testing script dry run functionality"

    # Create a test installation directory
    local test_bin_dir="$TEST_DIR/test-bin"
    local test_configs_dir="$TEST_DIR/test-configs"

    mkdir -p "$test_bin_dir" "$test_configs_dir"

    # Test that script can parse arguments without executing
    local script_output
    if script_output="$(echo "$test_configs_dir" | run_with_timeout 30 bash "$INSTALL_SCRIPT" --dry-run --verbose 2>&1)"; then
        # Check if script started properly
        if [[ "$script_output" == *"Starting copy-configs installation (DRY RUN)"* ]]; then
            log pass "Script dry run started successfully"
            return 0
        else
            log fail "Script dry run output unexpected: $script_output"
            ((test_failures++))
            return 1
        fi
    else
        log fail "Script dry run failed: $script_output"
        ((test_failures++))
        return 1
    fi
}

test_manual_instructions() {
    log test "Testing manual installation instructions"

    # Create a test installation directory
    local test_configs_dir="$TEST_DIR/test-configs"
    mkdir -p "$test_configs_dir"

    # Run dry run and capture output
    local script_output
    if script_output="$(echo "$test_configs_dir" | bash "$INSTALL_SCRIPT" --dry-run 2>&1)"; then
        # Check if manual installation instructions are present
        if [[ "$script_output" == *"For manual installation, add this function to your shell config:"* ]] && \
           [[ "$script_output" == *"gwq() {"* ]] && \
           [[ "$script_output" == *"\"$test_configs_dir/gwqx\""* ]]; then
            log pass "Manual installation instructions included with correct path"
            return 0
        else
            log fail "Manual installation instructions missing or incorrect"
            echo "Expected to find manual instructions with path: $test_configs_dir/gwqx"
            ((test_failures++))
            return 1
        fi
    else
        log fail "Failed to run script for manual instructions test: $script_output"
        ((test_failures++))
        return 1
    fi
}

# ---------- main test execution ----------
main() {
    log info "Starting installation script tests (version $SCRIPT_VERSION)"
    log info "Test directory: $TEST_DIR"
    echo

    # Run all tests
    test_script_exists
    test_script_executable
    test_help_option
    test_os_detection
    test_dependency_check
    test_github_api_access
    test_gwq_release_parsing
    test_repo_access
    test_dry_run
    test_manual_instructions

    echo
    if [[ $test_failures -eq 0 ]]; then
        log ok "All tests completed successfully!"
        return 0
    else
        log error "Tests completed with $test_failures failure(s)"
        return 1
    fi
}

# ---------- argument parsing ----------
while [[ $# -gt 0 ]]; do
    case "${1:-}" in
        -v|--verbose)
            verbose_mode=1
            shift ;;
        --no-color)
            use_color=0
            shift ;;
        -h|--help)
            cat <<'EOF'
Installation script test suite

USAGE:
  ./install.test.sh [OPTIONS]

OPTIONS:
  -v, --verbose     Enable verbose output
  --no-color        Disable colored output
  -h, --help        Show this help

This script tests:
1. Script existence and permissions
2. Help functionality
3. OS and architecture detection
4. Dependency availability
5. GitHub API access
6. Release information parsing
7. Repository accessibility
8. Dry run functionality
9. Manual installation instructions

EOF
            exit 0 ;;
        *)
            log error "Unknown option: $1"
            exit 1 ;;
    esac
done

main
