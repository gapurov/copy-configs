#!/usr/bin/env bash

set -euo pipefail

# ---------- constants ----------
readonly SCRIPT_VERSION="1.0.0"
readonly TEST_DIR="$(mktemp -d)"
readonly INSTALL_SCRIPT="$(dirname "$0")/../install.sh"

# ---------- global variables ----------
use_color=1
is_tty=0
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
        log ok "Full installation test passed!"
    else
        log error "Full installation test failed (failures: $test_failures, exit code: $exit_code)"
    fi
}

trap cleanup EXIT

# ---------- test installation ----------
test_full_installation() {
    log test "Testing complete installation process"

    # Set up test environment
    local test_bin_dir="$TEST_DIR/bin"
    local test_configs_dir="$TEST_DIR/configs"
    local test_home_dir="$TEST_DIR/home"

    mkdir -p "$test_bin_dir" "$test_configs_dir" "$test_home_dir"

    # Use isolated HOME so shell rc modifications happen in temp, not user rc
    export HOME="$test_home_dir"

    # Temporarily modify PATH to include our test directories
    export PATH="$test_bin_dir:$PATH"

    log info "Test directories:"
    log info "  Binary dir: $test_bin_dir"
    log info "  Config dir: $test_configs_dir"
    log info "  HOME dir:   $HOME"

    # Create a modified version of the install script that uses our test directories
    local test_install_script="$TEST_DIR/test-install.sh"

    # Copy the install script and replace the setup_directories function
    sed '/^setup_directories() {$/,/^}$/c\
setup_directories() {\
    bin_dir="'$test_bin_dir'"\
    configs_dir="'$test_configs_dir'"\
    \
    log info "Using test binary directory: $bin_dir"\
    log info "Using test configs directory: $configs_dir"\
    \
    mkdir -p "$bin_dir" "$configs_dir"\
    \
    log verb "Binary directory: $bin_dir"\
    log verb "Configs directory: $configs_dir"\
}' "$INSTALL_SCRIPT" > "$test_install_script"

    chmod +x "$test_install_script"

    # Run the installation with automatic input
    log info "Running installation script..."

    if command -v timeout >/dev/null 2>&1; then
        echo "$test_configs_dir" | timeout 120 bash "$test_install_script" --verbose
    else
        echo "$test_configs_dir" | bash "$test_install_script" --verbose
    fi
    if [[ $? -eq 0 ]]; then
        log pass "Installation script completed successfully"
    else
        log fail "Installation script failed or timed out"
        ((test_failures++))
        return 1
    fi

    # Verify gwq installation
    log test "Verifying gwq installation"
    if [[ -f "$test_bin_dir/gwq" && -x "$test_bin_dir/gwq" ]]; then
        log pass "gwq binary installed and executable"

        # Test gwq functionality
        if "$test_bin_dir/gwq" --help >/dev/null 2>&1; then
            log pass "gwq binary works correctly"
        else
            log fail "gwq binary not functional"
            ((test_failures++))
        fi
    else
        log fail "gwq binary not found or not executable"
        ((test_failures++))
    fi

    # Verify copy-configs installation
    log test "Verifying copy-configs installation"
    if [[ -f "$test_configs_dir/copy-configs.sh" && -x "$test_configs_dir/copy-configs.sh" ]]; then
        log pass "copy-configs.sh installed and executable"

        # Test copy-configs functionality
        if "$test_configs_dir/copy-configs.sh" --help >/dev/null 2>&1; then
            log pass "copy-configs.sh works correctly"
        else
            log fail "copy-configs.sh not functional"
            ((test_failures++))
        fi
    else
        log fail "copy-configs.sh not found or not executable"
        ((test_failures++))
    fi

    # Verify gwqx installation (optional, may not exist in repository)
    log test "Verifying gwqx installation"
    if [[ -f "$test_configs_dir/gwqx" && -x "$test_configs_dir/gwqx" ]]; then
        log pass "gwqx installed and executable"

        # Test gwqx functionality
        if "$test_configs_dir/gwqx" --help >/dev/null 2>&1; then
            log pass "gwqx works correctly"
        else
            log fail "gwqx not functional"
            ((test_failures++))
        fi
    else
        log warn "gwqx not found (may not exist in repository)"
    fi

    # Note: Symlinks are no longer created by the installation script
    log test "Verifying no symlinks created"
    if [[ ! -L "$test_bin_dir/copy-configs" && ! -L "$test_bin_dir/gwqx" ]]; then
        log pass "No unwanted symlinks created"
    else
        log warn "Unexpected symlinks found"
    fi

    return 0
}

# ---------- main test execution ----------
main() {
    log info "Starting full installation test (version $SCRIPT_VERSION)"
    log info "Test directory: $TEST_DIR"
    echo

    if [[ ! -f "$INSTALL_SCRIPT" ]]; then
        log error "Install script not found: $INSTALL_SCRIPT"
        exit 1
    fi

    # Run the full installation test
    test_full_installation

    echo
    if [[ $test_failures -eq 0 ]]; then
        log ok "Full installation test completed successfully!"
        return 0
    else
        log error "Full installation test completed with $test_failures failure(s)"
        return 1
    fi
}

main "$@"
