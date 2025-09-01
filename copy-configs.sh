#!/usr/bin/env bash
# copy-configs — Universal configuration file copying utility
# Version: 0.0.2
#
# SUMMARY
#   Copies an explicit set of local files/dirs (e.g., .env*, .cursor/, CLAUDE.md)
#   from the source directory into specified target directories, preserving relative paths.
#   Missing items are skipped. Works with any directory structure.

set -euo pipefail

# ---------- constants ----------
readonly REQUIRED_DEPS=(rsync)

# Default files to copy when no config exists
readonly DEFAULT_COPY_PATTERNS=(
    ".env*"
    "CLAUDE.md"
    "GEMINI.md"
    "AGENTS.md"
    "AGENT.md"
    ".claude/"
    ".cursor/"
    ".augment/"
    ".clinerules/"
    ".vscode/settings.json"
)

"${_COPY_CONFIGS_SH_SOURCED_ALREADY:-false}" && return 0 || true

# ---------- global configuration (bash 3.2 compatible) ----------
USE_COLOR=1
IS_TTY=0
CFG_OVERRIDE=""
CONFLICT_MODE="skip"      # skip|overwrite|backup
VERBOSE_MODE=0
DEBUG_MODE=0
DRY_RUN_MODE=0
SOURCE_ROOT_OVERRIDE=""

# ---------- cached command checks (disabled for bash 3.2) ----------
# On macOS bash 3.2, associative arrays are unavailable. We keep a simple
# check without caching since the number of deps is tiny.

# ---------- runtime state ----------
TARGET_PATHS=()

# ---------- initialization ----------
# Cache TTY detection for performance
[[ -t 1 ]] && IS_TTY=1

# ---------- logging ----------
log() {
    local level="$1"; shift
    local prefix icon color output_fd=1

    case "$level" in
        info)  prefix='>>' icon='>>'; color='36' ;;
        ok)    prefix='✓'  icon='✓';  color='32' ;;
        warn)  prefix='--' icon='--'; color='90'; output_fd=2 ;;
        error) prefix='!!' icon='!!'; color='31'; output_fd=2 ;;
        verb)  [[ ${VERBOSE_MODE} -eq 1 ]] || return 0; prefix='**' icon='**'; color='35'; output_fd=2 ;;
        debug) [[ ${DEBUG_MODE} -eq 1 ]] || return 0; prefix='DD' icon='DD'; color='33'; output_fd=2 ;;
        dry)   [[ ${DRY_RUN_MODE} -eq 1 ]] || return 0; prefix='DRY' icon='DRY'; color='96'; output_fd=2 ;;
        *) log error "Unknown log level: $level"; return 1 ;;
    esac

    if [[ ${USE_COLOR} -eq 1 && ${IS_TTY} -eq 1 ]]; then
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

# ---------- cleanup and signal handling ----------
# Cleanup function for any temporary resources
cleanup() {
    # No temporary files to clean up in simplified version
    :
}

# Enhanced error handler
error_handler() {
    local exit_code=$?
    log error "Script failed with exit code $exit_code"
    exit $exit_code
}

# Signal handler for interruption
signal_handler() {
    log warn "Received signal, exiting..."
    exit 130
}

# Set up signal handlers
trap error_handler ERR
trap signal_handler INT TERM

# ---------- cached command checking ----------
# Command existence check (no caching for bash 3.2)
has_command() {
    command -v "$1" >/dev/null 2>&1
}

# ---------- file existence utility ----------
# Check if file or symlink exists (optimized pattern)
# Args: path
# Returns: 0 if exists, 1 if not
file_exists() {
    [[ -e "$1" || -L "$1" ]]
}

# ---------- dependency management ----------
# Check that all required dependencies are available
# Globals: REQUIRED_DEPS (readonly array)
# Returns: exits with code 1 if dependencies missing
check_dependencies() {
    local missing=()
    local dep

    for dep in "${REQUIRED_DEPS[@]}"; do
        if ! has_command "$dep"; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log error "Missing required commands: ${missing[*]}"
        die 1
    fi

    log debug "All dependencies verified: ${REQUIRED_DEPS[*]}"
}

# Defer dependency check until after args are parsed so --help works offline

# ---------- help ----------
print_help() {
    cat <<'EOF'
Usage: copy-configs [OPTIONS] [--target PATH]
       echo "path/to/target" | copy-configs [OPTIONS]
       copy-configs [OPTIONS] < target_paths.txt

OPTIONS:
  --config, -c FILE     Path to rules file (overrides default search)
  --source, -s PATH     Explicit source root to copy from
  --conflict, -C MODE   skip|overwrite|backup   (default: skip)
  --target, -t PATH     Explicit target path (can be used multiple times)
  --no-color            Disable ANSI colors in output
  --verbose, -v         Enable verbose output
  --debug               Enable debug output
  --dry-run, -n         Show what would be done without executing
  --help, -h            Show help

EXAMPLES:
  # Via pipe
  echo "/path/to/target" | copy-configs
  echo "/path/to/target" | copy-configs --verbose

  # Via file
  copy-configs < target_paths.txt

  # Via command line argument
  copy-configs --target /path/to/target
  copy-configs -t /path/to/dir1 -t /path/to/dir2

  # Default behavior (copies .env*, CLAUDE.md, .cursor/, .vscode/settings.json)
  copy-configs --target /path/to/target  # No config file needed
EOF
}

# ---------- input validation ----------
validate_conflict_mode() {
    local mode="$1"
    case "$mode" in
        skip|overwrite|backup) return 0 ;;
                *) log error "Invalid --conflict '$mode' (use: skip|overwrite|backup)"; return 1 ;;
    esac
}

# Validate configuration file exists and is readable
# Args: config_file - path to configuration file
# Returns: 0 if valid, 1 if invalid
validate_config_file() {
    local config_file="$1"

    if [[ ! -f "$config_file" || ! -r "$config_file" ]]; then
        log error "Config file not accessible: $config_file"
        return 1
    fi

    return 0
}

validate_path_safety() {
    local path="$1"

    # Check for path traversal attempts
    case "$path" in
        */../*|../*|*/..|..)
            log error "Path traversal detected in: $path"
            return 1 ;;
        /*)
            log error "Absolute paths not allowed in config: $path"
            return 1 ;;
        ~/*)
            log error "Home directory paths not allowed in config: $path"
            return 1 ;;
    esac

    return 0
}

# Validate target path is writable and accessible
# Args: target_path
# Returns: 0 if valid, 1 if invalid
validate_target_path() {
    local target_path="$1"

    # Check if path exists and is a writable directory
    if [[ ! -d "$target_path" || ! -w "$target_path" ]]; then
        log error "Target path is not a writable directory: $target_path"
        return 1
    fi

    return 0
}

# ---------- parse args ----------
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "${1:-}" in
            -h|--help)
                print_help; exit 0 ;;
            -c|--config)
                [[ $# -ge 2 ]] || { log error "Missing argument for $1"; exit 1; }
                CFG_OVERRIDE="$2"; shift 2; continue ;;
            -s|--source)
                [[ $# -ge 2 ]] || { log error "Missing argument for $1"; exit 1; }
                SOURCE_ROOT_OVERRIDE="$2"; shift 2; continue ;;
            -C|--conflict|--copy-on-conflict)
                [[ $# -ge 2 ]] || { log error "Missing argument for $1"; exit 1; }
                validate_conflict_mode "$2" || exit 1
                CONFLICT_MODE="$2"
                shift 2; continue ;;
            -t|--target)
                [[ $# -ge 2 ]] || { log error "Missing argument for $1"; exit 1; }
                TARGET_PATHS+=("$2"); shift 2; continue ;;
            --no-color)
                USE_COLOR=0; shift; continue ;;
            -v|--verbose)
                VERBOSE_MODE=1; shift; continue ;;
            --debug)
                DEBUG_MODE=1; VERBOSE_MODE=1; shift; continue ;;
            -n|--dry-run)
                DRY_RUN_MODE=1; VERBOSE_MODE=1; shift; continue ;;
            *)
                log error "Unknown argument: $1"
                print_help
                exit 1 ;;
        esac
    done
}

parse_arguments "$@"

log debug "Parsed arguments: verbose=${VERBOSE_MODE} debug=${DEBUG_MODE} dry_run=${DRY_RUN_MODE}"
log debug "Target paths from args: ${TARGET_PATHS[*]:-<none>}"
log debug "Config override: ${CFG_OVERRIDE:-<none>}"
log debug "Conflict mode: ${CONFLICT_MODE}"

# Now that args are parsed, verify deps (resolve source root after function is defined)
check_dependencies

# ---------- repo validation ----------
get_source_root() {
    local root
    if has_command git; then
        if root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
            log verb "Source root (git): $root"
            printf '%s' "$root"
            return 0
        fi
    fi
    # Fallback to current directory if not in a git repo
    root="$(pwd)"
    log warn "Not in a git repo; using current directory as source root: $root"
    printf '%s' "$root"
}

# Resolve source root after function is defined
if [[ -n "${SOURCE_ROOT_OVERRIDE}" ]]; then
    source_root="${SOURCE_ROOT_OVERRIDE}"
    log verb "Source root (override): $source_root"
else
    source_root="$(get_source_root)"
fi

# ---------- config resolution ----------
find_config_file() {
    local config_paths=(
        "${CFG_OVERRIDE}"
        "$source_root/.copyconfigs"
        "$HOME/.config/copy-configs/config"
        "$HOME/.config/gwq/copyconfigs"
    )

    local cfg_file
    for cfg_file in "${config_paths[@]}"; do
        # Allow non-regular files for explicit override (e.g., process substitution)
        if [[ -n $cfg_file && $cfg_file == "${CFG_OVERRIDE}" && -r $cfg_file ]]; then
            printf '%s' "$cfg_file"
            return 0
        fi
        [[ -n $cfg_file && -f $cfg_file ]] || continue
        if validate_config_file "$cfg_file"; then
            printf '%s' "$cfg_file"
            return 0
        elif [[ $cfg_file == "${CFG_OVERRIDE}" ]]; then
            exit 1  # Fail if explicit override is invalid
        fi
    done
}

cfg="$(find_config_file)"


# ---------- input collection ----------
# Read target paths from stdin if no --target args provided
read_stdin_paths() {
    if [[ ${#TARGET_PATHS[@]} -eq 0 ]] && [[ ! -t 0 ]]; then
        log verb "Reading target paths from stdin"
        while IFS= read -r line || [[ -n $line ]]; do
            # Trim whitespace
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            [[ -n $line ]] && TARGET_PATHS+=("$line")
        done
    fi
}

read_stdin_paths

# ---------- input validation ----------
[[ ${#TARGET_PATHS[@]} -eq 0 ]] && { log error "No target paths provided"; exit 1; }

log info "Processing ${#TARGET_PATHS[@]} target path(s)"
log debug "Target paths: ${TARGET_PATHS[*]}"


# ========== CONFIGURATION PARSING ==========

# Parse a single config rule line into source and destination
# Args: raw - raw line from config file
#       rule_array_ref - name of array variable to store result
# Returns: 0 if valid rule parsed, 1 if invalid/empty
# Side effects: validates path safety; populates globals: PARSED_SRC, PARSED_DEST
parse_config_rule() {
    local raw="$1" rule_array_ref="$2"
    local -a parsed_rule=()

    # Strip CR and comments
    raw="${raw%%$'\r'}"
    raw="${raw%%#*}"

    # Trim whitespace
    raw="${raw#"${raw%%[![:space:]]*}"}"
    raw="${raw%"${raw##*[![:space:]]}"}"

    [[ -z $raw ]] && return 1

    if [[ $raw == *:* ]]; then
        parsed_rule=("${raw%%:*}" "${raw#*:}")
    else
        parsed_rule=("$raw" "$raw")
    fi

    # Validate path safety for both source and destination
    if ! validate_path_safety "${parsed_rule[0]}" || ! validate_path_safety "${parsed_rule[1]}"; then
        return 1
    fi

    # Set global outputs for bash 3.2 compatibility
    PARSED_SRC="${parsed_rule[0]}"
    PARSED_DEST="${parsed_rule[1]}"
    return 0
}

# ========== FILE OPERATIONS ==========

handle_file_conflict() {
    local dest="$1" wtree="$2"
    local relative_dest="${dest#$wtree/}"

    case "${CONFLICT_MODE}" in
        skip)
        log warn "keep (exists): $relative_dest"
            return 1 ;;
        backup)
            local backup="${dest}.bak-$(date +%Y%m%d-%H%M%S)"
            local relative_backup="${backup#$wtree/}"
            log info "backup: $relative_dest -> $relative_backup"
            mv "$dest" "$backup" ;;
        overwrite)
            return 0 ;;
    esac
}

# ---------- file matching ----------
find_matching_files() {
    local pattern="$1" source_dir="$2"

    # Use a subshell to isolate directory change and glob settings
    (
        cd "$source_dir" 2>/dev/null || exit 1
        shopt -s nullglob dotglob
        for m in $pattern; do
            printf '%s\n' "$m"
        done
    )
}

# ---------- copy operations ----------
# Prepare destination path for explicit mapping
# Args: target, dest_path
# Returns: final_dest via stdout
prepare_explicit_dest() {
    local target="$1" dest_path="$2"
    local final_dest="$target/$dest_path"

    # Handle trailing slash for directories
    [[ $dest_path == */ ]] && final_dest="${final_dest%/}/"
    printf '%s' "$final_dest"
}

# Prepare destination path for relative structure
# Args: src, target
# Returns: final_dest via stdout
prepare_relative_dest() {
    local src="$1" target="$2"
    local rel="${src#$source_root/}"
    printf '%s' "$target/$rel"
}

# Ensure destination directory exists
# Args: dest_path
ensure_dest_dir() {
    local dest_path="$1"
    mkdir -p "$(dirname "$dest_path")" 2>/dev/null || true
}

readonly RSYNC_BACKUP_SUFFIX=".bak-$(date +%Y%m%d-%H%M%S)"

# Build rsync options based on flags and conflict mode
build_rsync_args() {
    RSYNC_ARGS=("-a")
    [[ $VERBOSE_MODE -eq 1 ]] && RSYNC_ARGS+=("-v")
    case "$CONFLICT_MODE" in
        skip)
            RSYNC_ARGS+=("--ignore-existing") ;;
        backup)
            RSYNC_ARGS+=("--backup" "--suffix=$RSYNC_BACKUP_SUFFIX" "--checksum") ;;
        overwrite)
            : ;;
    esac
}

# Perform the actual file copy operation
# Args: src, dest, description
# Returns: 0 on success, 1 on failure
perform_copy() {
    local src="$1" dest="$2" desc="$3"
    build_rsync_args

    if rsync "${RSYNC_ARGS[@]}" -- "$src" "$dest"; then
        log ok "copied: $desc"
        return 0
    else
        log error "Failed to copy $src to $dest"
        return 1
    fi
}

# Perform relative copy with rsync --relative
# Args: rel_path, target
# Returns: 0 on success, 1 on failure
perform_relative_copy() {
    local rel_path="$1" target="$2"
    build_rsync_args

    if (cd "$source_root" && rsync "${RSYNC_ARGS[@]}" --relative -- "./$rel_path" "$target/"); then
        log ok "copied: $rel_path"
        return 0
    else
        log error "Failed to copy $rel_path with relative structure"
        return 1
    fi
}

copy_file() {
    local src="$1" target="$2" dest_path="${3:-}"
    local final_dest

    if [[ -n $dest_path ]]; then
        # Explicit mapping
        final_dest="$(prepare_explicit_dest "$target" "$dest_path")"

        if [[ ${DRY_RUN_MODE} -eq 1 ]]; then
            log dry "Would copy: $src -> ${dest_path}"
            return 0
        fi

        ensure_dest_dir "$final_dest"
        perform_copy "$src" "$final_dest" "$(basename "$src") -> $dest_path"
    else
        # Relative structure from source_root
        final_dest="$(prepare_relative_dest "$src" "$target")"

        if [[ ${DRY_RUN_MODE} -eq 1 ]]; then
            local rel="${src#$source_root/}"
            log dry "Would copy with relative structure: $rel -> $target/"
            return 0
        fi

        local rel="${src#$source_root/}"
        perform_relative_copy "$rel" "$target"
    fi
}


# ---------- main copy engine ----------
copy_into_target() {
    local target="$1"
    local patterns_to_process

    log verb "Processing target: $target"

    if [[ ! -d $source_root ]]; then
        log error "Source root does not exist: $source_root"
        return 1
    fi

    if [[ -z $cfg ]]; then
        log info "No config file found, using default patterns: ${DEFAULT_COPY_PATTERNS[*]}"
        patterns_to_process=("${DEFAULT_COPY_PATTERNS[@]}")
        process_patterns "$target" "" "${patterns_to_process[@]}"
    else
        log info "Using config: $cfg"
        process_config_file "$target" "$cfg"
    fi
}

process_patterns() {
    local target="$1" dest_override="$2"
    shift 2
    local -a patterns=("$@")

    local pattern
    for pattern in "${patterns[@]}"; do
        log debug "Processing pattern: '$pattern'"

        local count=0 src_file
        while IFS= read -r src_file; do
            [[ -z $src_file ]] && continue
            file_exists "$source_root/$src_file" || { log warn "skip (missing): $src_file"; continue; }

            if [[ -n $dest_override && $dest_override != "$pattern" ]]; then
                copy_file "$source_root/$src_file" "$target" "$dest_override"
            else
                copy_file "$source_root/$src_file" "$target"
            fi
            count=$((count+1))
        done < <(find_matching_files "$pattern" "$source_root")

        if [[ $count -eq 0 ]]; then
            log verb "skip (missing): $pattern"
        else
            log verb "Found matches for '$pattern': $count files"
        fi
    done
}

process_config_file() {
    local target="$1" config_file="$2"

    while IFS= read -r line || [[ -n $line ]]; do
        parse_config_rule "$line" _ || continue
        local src_pattern="$PARSED_SRC" dest_rel="$PARSED_DEST"
        process_patterns "$target" "$dest_rel" "$src_pattern"
    done < "$config_file"
}


# ---------- main processing loop ----------
process_targets() {
    local target_path

    for tp in "${TARGET_PATHS[@]}"; do
        [[ -z $tp ]] && continue

        if [[ $tp == /* ]]; then
            target_path="$tp"
        else
            target_path="$(cd "$tp" 2>/dev/null && pwd)" || {
                log warn "Invalid target path: $tp"
                continue
            }
        fi

        if ! validate_target_path "$target_path"; then
            log warn "Skipping invalid target: $target_path"
            continue
        fi

        log info "Copying files into: $target_path"
        copy_into_target "$target_path"
    done
}

# ========== MAIN EXECUTION ==========
process_targets

# Final cleanup (in case any temp files were left)
cleanup

log ok "Done."

# ========== FUNCTION REFERENCE ==========
#
# CORE EXECUTION FLOW:
#   main() -> parse_arguments() -> check_dependencies() -> get_source_root()
#        -> read_stdin_paths() -> process_targets() -> copy_into_target()
#        -> process_patterns() -> copy_file()
#
# KEY UTILITY FUNCTIONS:
#   has_command()        - Cached command existence checking
#   file_exists()        - Optimized file/symlink existence check
#   validate_*()         - Path and configuration validation
#   perform_*()          - Low-level copy operations
#   prepare_*()          - Path preparation utilities
#   log()                - Structured logging with levels and colors
#   cleanup()            - Resource cleanup on exit/error
#
# CONFIGURATION:
#   CONFIG[]             - Global configuration associative array
#   COMMAND_CACHE[]      - Command existence cache
#   TARGET_PATHS[]       - Target directories to process
#
# ERROR HANDLING:
#   - All functions return 0 on success, 1 on failure
#   - die() for fatal errors requiring immediate exit
#   - error_handler() for ERR trap with error reporting
#   - signal_handler() for INT/TERM with graceful exit
