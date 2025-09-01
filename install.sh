#!/usr/bin/env bash
# install.sh — Installation script for copy-configs and gwq
# Version: 1.0.0
#
# SUMMARY
#   Downloads and installs gwq binary and copy-configs scripts.
#   Supports macOS, Linux, and Windows WSL.
#
# USAGE
#   curl -fsSL https://raw.githubusercontent.com/gapurov/copy-configs/refs/heads/main/install.sh | bash
#   or
#   ./install.sh

set -euo pipefail

# ---------- constants ----------
readonly SCRIPT_VERSION="1.0.0"
readonly GWQ_REPO="d-kuro/gwq"
readonly CONFIGS_REPO="gapurov/copy-configs"
readonly CONFIGS_BRANCH="main"

# Default installation paths
readonly DEFAULT_BIN_DIR="$HOME/.local/bin"
readonly DEFAULT_CONFIGS_DIR="$HOME/.local/bin/copy-configs"
readonly SYSTEM_BIN_DIR="/usr/local/bin"

# ---------- global variables ----------
use_color=1
is_tty=0
verbose_mode=0
dry_run=0
bin_dir=""
configs_dir=""
use_sudo=0
os_type=""
arch_type=""

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
        verb)  [[ $verbose_mode -eq 1 ]] || return 0; prefix='**' icon='**'; color='35' ;;
        *) log error "Unknown log level: $level"; return 1 ;;
    esac

    if [[ $use_color -eq 1 && $is_tty -eq 1 ]]; then
        printf "\033[${color}m${icon}\033[0m %s\n" "$*" >&$output_fd
    else
        printf "%s %s\n" "$prefix" "$*" >&$output_fd
    fi
}

# ---------- error handling ----------
die() {
    local code=${1:-1}
    exit $code
}

trap 'log error "Installation failed with exit code $?"' ERR

# ---------- system detection ----------
detect_os() {
    case "$(uname -s)" in
        Darwin*)
            os_type="darwin"
            ;;
        Linux*)
            if [[ -f /proc/version ]] && grep -q Microsoft /proc/version; then
                os_type="linux"  # WSL
                log info "Detected Windows WSL environment"
            else
                os_type="linux"
            fi
            ;;
        CYGWIN*|MINGW*|MSYS*)
            log error "Windows (non-WSL) is not supported. Please use WSL."
            exit 1
            ;;
        *)
            log error "Unsupported operating system: $(uname -s)"
            exit 1
            ;;
    esac
    log verb "Detected OS: $os_type"
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
            log error "Unsupported architecture: $(uname -m)"
            exit 1
            ;;
    esac
    log verb "Detected architecture: $arch_type"
}

# ---------- dependency checks ----------
check_dependencies() {
    local deps=(curl tar)
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log error "Missing required commands: ${missing[*]}"
        log error "Please install them first and retry"
        exit 1
    fi

    log verb "All dependencies verified: ${deps[*]}"
}

# ---------- directory setup ----------
setup_directories() {
    # Ask user where to install gwq
    log info "Where should gwq be installed?"
    if [[ $is_tty -eq 1 ]]; then
        read -p "Enter path (default: $SYSTEM_BIN_DIR): " bin_input
        bin_dir="${bin_input:-$SYSTEM_BIN_DIR}"
    else
        # Non-interactive mode, use default user directory to avoid sudo
        bin_dir="$DEFAULT_BIN_DIR"
        log info "Non-interactive mode, using: $bin_dir"
    fi

    # Check if chosen directory requires sudo
    if [[ -w "$bin_dir" ]] 2>/dev/null || [[ -w "$(dirname "$bin_dir")" ]] 2>/dev/null; then
        # Can write without sudo
        use_sudo=0
        log info "Using directory: $bin_dir"
        mkdir -p "$bin_dir" 2>/dev/null || true
    else
        # Directory requires elevated permissions
        log info "Directory $bin_dir requires elevated permissions"
        if [[ $is_tty -eq 1 ]]; then
            # Test sudo access
            if sudo -n true 2>/dev/null || sudo -v; then
                use_sudo=1
                log info "Using directory with sudo: $bin_dir"
            else
                log error "sudo access denied and cannot write to $bin_dir"
                log error "Please choose a different directory or run with appropriate permissions"
                exit 1
            fi
        else
            log error "Non-interactive mode and cannot write to $bin_dir"
            exit 1
        fi
    fi

    # Ask user for configs directory
    log info "Where should the copy-configs scripts be installed?"
    if [[ $is_tty -eq 1 ]]; then
        read -p "Enter path (default: $DEFAULT_CONFIGS_DIR): " configs_input
        configs_dir="${configs_input:-$DEFAULT_CONFIGS_DIR}"
    else
        # In non-interactive mode, attempt to read a single line from stdin; fallback to default
        local configs_input=""
        if IFS= read -r -t 1 configs_input; then
            configs_dir="${configs_input:-$DEFAULT_CONFIGS_DIR}"
            log info "Non-interactive input detected, using: $configs_dir"
        else
            configs_dir="$DEFAULT_CONFIGS_DIR"
            log info "Non-interactive mode, using: $configs_dir"
        fi
    fi

    if [[ ! -d "$configs_dir" ]]; then
        log info "Creating directory: $configs_dir"
        mkdir -p "$configs_dir"
    fi

    log verb "Binary directory: $bin_dir"
    log verb "Configs directory: $configs_dir"
}

# ---------- gwq installation ----------
get_latest_gwq_release() {
    log info "Fetching latest gwq release information..." >&2

    local api_url="https://api.github.com/repos/$GWQ_REPO/releases/latest"
    local release_data

    if ! release_data="$(curl -fsSL "$api_url")"; then
        log error "Failed to fetch release information from GitHub"
        exit 1
    fi

    # Extract tag name (version)
    local version
    if ! version="$(echo "$release_data" | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')"; then
        log error "Failed to parse release version"
        exit 1
    fi

    log verb "Latest gwq version: $version" >&2

    # Convert OS and arch to the format used by gwq releases
    local release_os release_arch
    case "$os_type" in
        darwin) release_os="Darwin" ;;
        linux) release_os="Linux" ;;
        *) release_os="$os_type" ;;
    esac

    case "$arch_type" in
        amd64) release_arch="x86_64" ;;
        arm64) release_arch="arm64" ;;
        *) release_arch="$arch_type" ;;
    esac

    # Find the appropriate asset
    local asset_name="gwq_${release_os}_${release_arch}.tar.gz"
    local download_url

    if ! download_url="$(echo "$release_data" | grep "browser_download_url.*$asset_name" | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')"; then
        log error "Could not find download URL for $asset_name"
        log error "Available assets:"
        echo "$release_data" | grep '"name"' | grep '\.tar\.gz' | sed 's/.*"name": *"\([^"]*\)".*/\1/' | sed 's/^/  /' >&2
        exit 1
    fi

    log verb "Download URL: $download_url" >&2
    echo "$download_url"
}

download_and_install_gwq() {
    if [[ $dry_run -eq 1 ]]; then
        log info "DRY RUN: Would download and install gwq"
        return 0
    fi

    local download_url
    download_url="$(get_latest_gwq_release)"

    log info "Downloading gwq..."

    local temp_dir
    temp_dir="$(mktemp -d)"
    trap 'rm -rf "$temp_dir"' EXIT

    local archive_path="$temp_dir/gwq.tar.gz"

    if ! curl -fsSL -o "$archive_path" "$download_url"; then
        log error "Failed to download gwq"
        exit 1
    fi

    log info "Extracting gwq..."
    if ! tar -xzf "$archive_path" -C "$temp_dir"; then
        log error "Failed to extract gwq archive"
        exit 1
    fi

    # Find the gwq binary in the extracted files
    local gwq_binary
    gwq_binary="$(find "$temp_dir" -name "gwq" -type f | head -1)"

    if [[ -z "$gwq_binary" ]]; then
        log error "Could not find gwq binary in extracted archive"
        exit 1
    fi

    log info "Installing gwq to $bin_dir/gwq"
    if [[ $use_sudo -eq 1 ]]; then
        if ! sudo cp "$gwq_binary" "$bin_dir/gwq"; then
            log error "Failed to install gwq binary with sudo"
            exit 1
        fi
        if ! sudo chmod +x "$bin_dir/gwq"; then
            log error "Failed to make gwq executable with sudo"
            exit 1
        fi
    else
        if ! cp "$gwq_binary" "$bin_dir/gwq"; then
            log error "Failed to install gwq binary"
            exit 1
        fi
        if ! chmod +x "$bin_dir/gwq"; then
            log error "Failed to make gwq executable"
            exit 1
        fi
    fi

    # Ensure cleanup now even if later trap changes
    rm -rf "$temp_dir" 2>/dev/null || true
    trap - EXIT

    log ok "gwq installed successfully"
}

# ---------- copy-configs installation ----------
download_and_install_configs() {
    if [[ $dry_run -eq 1 ]]; then
        log info "DRY RUN: Would download and install copy-configs scripts"
        return 0
    fi

    log info "Downloading copy-configs scripts..."

    local temp_dir
    temp_dir="$(mktemp -d)"
    trap 'rm -rf "$temp_dir"' EXIT

    local archive_url="https://github.com/$CONFIGS_REPO/archive/refs/heads/$CONFIGS_BRANCH.tar.gz"
    local archive_path="$temp_dir/configs.tar.gz"

    if ! curl -fsSL -o "$archive_path" "$archive_url"; then
        log error "Failed to download copy-configs repository"
        exit 1
    fi

    log info "Extracting copy-configs..."
    if ! tar -xzf "$archive_path" -C "$temp_dir"; then
        log error "Failed to extract copy-configs archive"
        exit 1
    fi

    # Find the extracted repository directory
    local repo_dir
    repo_dir="$(find "$temp_dir" -name "copy-configs-main" -type d | head -1)"

    if [[ -z "$repo_dir" ]]; then
        log error "Could not find copy-configs repository directory"
        exit 1
    fi

    log info "Installing copy-configs scripts to $configs_dir"

    # Copy the scripts
    if [[ -f "$repo_dir/copy-configs.sh" ]]; then
        if ! cp "$repo_dir/copy-configs.sh" "$configs_dir/copy-configs.sh"; then
            log error "Failed to copy copy-configs.sh"
            exit 1
        fi
    else
        log error "copy-configs.sh not found in repository"
        exit 1
    fi

    if [[ -f "$repo_dir/gwqx" ]]; then
        if ! cp "$repo_dir/gwqx" "$configs_dir/gwqx"; then
            log error "Failed to copy gwqx"
            exit 1
        fi
    else
        log warn "gwqx not found in repository, skipping"
    fi

    # Copy additional files if they exist
    for file in LICENSE README.md; do
        if [[ -f "$repo_dir/$file" ]]; then
            cp "$repo_dir/$file" "$configs_dir/" 2>/dev/null || true
        fi
    done

    # Make scripts executable
    if [[ $dry_run -eq 0 ]]; then
        chmod +x "$configs_dir"/*.sh 2>/dev/null || true
        chmod +x "$configs_dir/gwqx" 2>/dev/null || true
    else
        log info "DRY RUN: Would make scripts executable"
    fi

    # Ensure cleanup now even if later trap changes
    rm -rf "$temp_dir" 2>/dev/null || true
    trap - EXIT

    log ok "copy-configs scripts installed successfully"
}


# ---------- path verification ----------
check_path() {
    if [[ ":$PATH:" == *":$bin_dir:"* ]]; then
        log ok "Directory $bin_dir is already in PATH"
        return 0
    else
        log warn "Directory $bin_dir is not in PATH"
        return 1
    fi
}

# ---------- gwq function installation ----------
install_gwq_function() {
    log info "Installing gwq function..."

    # Check if gwqx exists in the configs directory
    local gwqx_path="$configs_dir/gwqx"
    if [[ ! -f "$gwqx_path" ]]; then
        log warn "gwqx not found at $gwqx_path, skipping gwq function installation"
        return 0
    fi

    # Detect the user's shell and config file
    local user_shell="${SHELL:-/bin/sh}"
    local config_file=""

    case "$user_shell" in
        */zsh)
            config_file="$HOME/.zshrc"
            ;;
        */bash)
            # Check for .bashrc first, then .bash_profile
            if [[ -f "$HOME/.bashrc" ]]; then
                config_file="$HOME/.bashrc"
            elif [[ -f "$HOME/.bash_profile" ]]; then
                config_file="$HOME/.bash_profile"
            else
                config_file="$HOME/.bashrc"  # Create .bashrc if neither exists
            fi
            ;;
        */fish)
            config_file="$HOME/.config/fish/config.fish"
            ;;
        *)
            config_file="$HOME/.profile"
            ;;
    esac

    log verb "Target shell: $user_shell, config file: $config_file"

    # Check if the function already exists
    if [[ -f "$config_file" ]] && grep -q "^gwq()" "$config_file" 2>/dev/null; then
        log ok "gwq function already exists in $config_file"
        return 0
    fi

    # Create config file directory if it doesn't exist
    local config_dir
    config_dir="$(dirname "$config_file")"
    if [[ ! -d "$config_dir" ]]; then
        if [[ $dry_run -eq 0 ]]; then
            mkdir -p "$config_dir"
            log verb "Created directory: $config_dir"
        else
            log info "DRY RUN: Would create directory: $config_dir"
        fi
    fi

    # Generate the function content
    local gwq_function="
# gwq function - intercepts 'addx' subcommand for enhanced functionality
gwq() {
    if [[ \"\${1:-}\" == \"addx\" ]]; then
        # Call gwqx for the addx subcommand
        shift
        \"$gwqx_path\" \"\$@\"
    else
        # Pass through to native gwq for all other commands
        \"$bin_dir/gwq\" \"\$@\"
    fi
}
"

    # Add the function to the config file
    if [[ $dry_run -eq 0 ]]; then
        if echo "$gwq_function" >> "$config_file"; then
            log ok "Added gwq function to $config_file"
        else
            log error "Failed to write gwq function to $config_file"
            return 1
        fi
    else
        log info "DRY RUN: Would add gwq function to $config_file"
    fi
}

# ---------- post-installation instructions ----------
show_instructions() {
    log ok "Installation completed successfully!"
    echo

    if ! check_path; then
        log info "To use the installed tools, add the following to your shell profile:"
        echo "  export PATH=\"$bin_dir:\$PATH\""
        echo
        log info "For bash, add to ~/.bashrc or ~/.bash_profile"
        log info "For zsh, add to ~/.zshrc"
        echo
        log info "Then restart your shell or run: source ~/.bashrc (or ~/.zshrc)"
        echo
    fi

    log info "Verify installation:"
    echo "  gwq --help"
    echo

    log info "The gwq function has been automatically added to your shell configuration."
    log info "After restarting your shell, you can use:"
    echo "  gwq addx -b feature/new-feature"
    echo

    log info "For manual installation, add this function to your shell config:"
    echo
    echo "# gwq function - intercepts 'addx' subcommand for enhanced functionality"
    echo "gwq() {"
    echo "    if [[ \"\${1:-}\" == \"addx\" ]]; then"
    echo "        # Call gwqx for the addx subcommand"
    echo "        shift"
    echo "        \"$configs_dir/gwqx\" \"\$@\""
    echo "    else"
    echo "        # Pass through to native gwq for all other commands"
    echo "        \"$bin_dir/gwq\" \"\$@\""
    echo "    fi"
    echo "}"
    echo
    echo "  # Copy configs to existing directory"
    echo "  echo '/path/to/target' | copy-configs"
    echo
    echo "  # Direct usage (requires full path)"
    echo "  echo '/path/to/target' | $configs_dir/copy-configs.sh"
    echo

    log info "Configuration:"
    echo "  Default files copied: .env*, CLAUDE.md, .cursor/, .vscode/settings.json"
    echo "  Custom config: .copyconfigs in your repo or ~/.config/copy-configs/config"
    echo

    log ok "Happy coding!"
}

# ---------- main execution ----------
main() {
    if [[ $dry_run -eq 1 ]]; then
        log info "Starting copy-configs installation (DRY RUN) (version $SCRIPT_VERSION)"
    else
        log info "Starting copy-configs installation (version $SCRIPT_VERSION)"
    fi

    detect_os
    detect_arch
    check_dependencies
    setup_directories

    download_and_install_gwq
    download_and_install_configs
    install_gwq_function

    show_instructions
}

# ---------- argument parsing ----------
while [[ $# -gt 0 ]]; do
    case "${1:-}" in
        -v|--verbose)
            verbose_mode=1
            shift ;;
        --dry-run)
            dry_run=1
            shift ;;
        --no-color)
            use_color=0
            shift ;;
        -h|--help)
            cat <<'EOF'
copy-configs installation script

USAGE:
  curl -fsSL https://raw.githubusercontent.com/gapurov/copy-configs/refs/heads/main/install.sh | bash
  or
  ./install.sh [OPTIONS]

OPTIONS:
  -v, --verbose     Enable verbose output
  --dry-run         Show what would be done without executing
  --no-color        Disable colored output
  -h, --help        Show this help

This script will:
1. Download and install the latest gwq binary
2. Download and install copy-configs scripts
3. Provide PATH configuration instructions

EOF
            exit 0 ;;
        *)
            log error "Unknown option: $1"
            exit 1 ;;
    esac
done

main
