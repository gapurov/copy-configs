#!/usr/bin/env bash
# copy-configs — Universal configuration file copying utility
# Version: 0.0.1
#
# SUMMARY
#   Copies an explicit set of local files/dirs (e.g., .env*, .cursor/, CLAUDE.md)
#   from the source directory into specified target directories, preserving relative paths.
#   Missing items are skipped. Works with any directory structure.
#
# REQUIREMENTS
#   - bash 4.0+ (required for associative arrays and improved features)
#   - git, rsync
#   - timeout (optional, for operation timeouts)
#
# USAGE
#   echo "path/to/target" | copy-configs [OPTIONS]
#   copy-configs [OPTIONS] < target_paths.txt
#   copy-configs [OPTIONS] --target path/to/target
#
# AUTHOR
#   Enhanced with Claude Code assistance for performance and reliability

set -euo pipefail

# ---------- constants ----------
readonly SCRIPT_VERSION="0.0.1"
readonly MAX_CONFIG_SIZE=1048576  # 1MB
readonly REQUIRED_DEPS=(git rsync)

# Default files to copy when no config exists
readonly DEFAULT_COPY_PATTERNS=(
    ".env*"
    "CLAUDE.md"
    ".cursor/"
    ".vscode/settings.json"
)

# ---------- global variables ----------
declare -g use_color=1 is_tty=0 source_root=""
declare -g cfg_override="" conflict_mode="skip"
declare -g verbose_mode=0 debug_mode=0 dry_run_mode=0
declare -g target_override=""
declare -ga TARGET_PATHS=()

# ---------- initialization ----------
# Cache TTY detection for performance
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
        verb)  [[ $verbose_mode -eq 1 ]] || return 0; prefix='**' icon='**'; color='35'; output_fd=2 ;;
        debug) [[ $debug_mode -eq 1 ]] || return 0; prefix='DD' icon='DD'; color='33'; output_fd=2 ;;
        dry)   [[ $dry_run_mode -eq 1 ]] || return 0; prefix='DRY' icon='DRY'; color='96'; output_fd=2 ;;
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

trap 'log error "Script failed with exit code $?"' ERR

# ---------- dependency management ----------
# Check that all required dependencies are available
# Globals: REQUIRED_DEPS (readonly array)
# Returns: exits with code 1 if dependencies missing
check_dependencies() {
    local missing=()
    local dep

    for dep in "${REQUIRED_DEPS[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
    log error "Missing required commands: ${missing[*]}"
        die 1
    fi

    log debug "All dependencies verified: ${REQUIRED_DEPS[*]}"
}

check_dependencies

# ---------- help ----------
print_help() {
    cat <<'EOF'
Usage: copy-configs [OPTIONS] [--target PATH]
       echo "path/to/target" | copy-configs [OPTIONS]
       copy-configs [OPTIONS] < target_paths.txt

OPTIONS:
  --config, -c FILE     Path to rules file (overrides default search)
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

# Validate configuration file exists, is readable, and reasonable size
# Args: config_file - path to configuration file
# Globals: MAX_CONFIG_SIZE (readonly)
# Returns: 0 if valid, 1 if invalid
validate_config_file() {
    local config_file="$1"

    if [[ ! -f $config_file ]]; then
        log error "Config file does not exist: $config_file"
        return 1
    fi

    if [[ ! -r $config_file ]]; then
        log error "Config file is not readable: $config_file"
        return 1
    fi

    # Prevent processing of extremely large files
    local file_size
    file_size="$(wc -c < "$config_file" 2>/dev/null || echo 0)"
    if [[ $file_size -gt $MAX_CONFIG_SIZE ]]; then
        log error "Config file too large (>$(( MAX_CONFIG_SIZE / 1024 ))KB): $config_file"
        return 1
    fi

    log debug "Config file validated: $config_file (${file_size} bytes)"
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

    # Check for null bytes and dangerous characters (but allow glob patterns)
    local clean_path="${path//[$'\0\n\r']/}"
    if [[ ${#clean_path} -ne ${#path} ]]; then
        log error "Invalid control characters in path: $path"
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
                cfg_override="$2"; shift 2; continue ;;
            -C|--conflict|--copy-on-conflict)
                [[ $# -ge 2 ]] || { log error "Missing argument for $1"; exit 1; }
                validate_conflict_mode "$2" || exit 1
                conflict_mode="$2"
                shift 2; continue ;;
            -t|--target)
                [[ $# -ge 2 ]] || { log error "Missing argument for $1"; exit 1; }
                TARGET_PATHS+=("$2"); shift 2; continue ;;
            --no-color)
                use_color=0; shift; continue ;;
            -v|--verbose)
                verbose_mode=1; shift; continue ;;
            --debug)
                debug_mode=1; verbose_mode=1; shift; continue ;;
            -n|--dry-run)
                dry_run_mode=1; verbose_mode=1; shift; continue ;;
            *)
                log error "Unknown argument: $1"
                print_help
                exit 1 ;;
        esac
    done
}

parse_arguments "$@"

log debug "Parsed arguments: verbose=$verbose_mode debug=$debug_mode dry_run=$dry_run_mode"
log debug "Target paths from args: ${TARGET_PATHS[*]:-<none>}"
log debug "Config override: ${cfg_override:-<none>}"
log debug "Conflict mode: $conflict_mode"

# ---------- repo validation ----------
get_source_root() {
    local root
    if ! root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
        log error "Please run from inside a git repository."
        exit 1
    fi
    log verb "Source root: $root"
    printf '%s' "$root"
}

source_root="$(get_source_root)"

# ---------- config resolution ----------
find_config_file() {
    local config_paths=(
        "$cfg_override"
        "$source_root/.copyconfigs"
        "$HOME/.config/copy-configs/config"
        "$HOME/.config/gwq/copyconfigs"
    )

    local cfg_file
    for cfg_file in "${config_paths[@]}"; do
        [[ -n $cfg_file && -f $cfg_file ]] || continue
        if validate_config_file "$cfg_file"; then
            printf '%s' "$cfg_file"
            return 0
        elif [[ $cfg_file == "$cfg_override" ]]; then
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
# Side effects: validates path safety, populates result array via nameref
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

    # Use nameref to return array
    local -n result_ref="$rule_array_ref"
    result_ref=("${parsed_rule[@]}")
    return 0
}

# ========== FILE OPERATIONS ==========

handle_file_conflict() {
    local dest="$1" wtree="$2"
    local relative_dest="${dest#$wtree/}"

    case "$conflict_mode" in
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

copy_file_to_dest() {
    local src="$1" dest="$2" want_dir="$3" wtree="$4"

    # Ensure dest ends with / if it should be a directory
    if [[ $want_dir -eq 1 && $dest != */ ]]; then
        dest="${dest}/"
    fi

    # Handle conflicts
    if [[ -e $dest || -L $dest ]]; then
        handle_file_conflict "$dest" "$wtree" || return 0
    fi

    mkdir -p "$(dirname "$dest")" 2>/dev/null || true

    # Copy with rsync for reliability
    if ! rsync -a "$src" "$dest"; then
        log error "Failed to copy $src to $dest"
        return 1
    fi
}

# ---------- file matching ----------
find_matching_files() {
    local pattern="$1" source_dir="$2"

    # Use subshell to contain glob settings and directory change
    (
        cd "$source_dir" || exit 1
        shopt -s nullglob dotglob
        # shellcheck disable=SC2206
        local -a matches=( $pattern )
        printf '%s\n' "${matches[@]}"
    )
}

# ---------- copy operations ----------
copy_file() {
    local src="$1" target="$2" dest_path="${3:-}"
    local final_dest

    if [[ -n $dest_path ]]; then
        # Explicit mapping
        final_dest="$target/$dest_path"
        [[ $dest_path == */ ]] && final_dest="${final_dest%/}/"

        if [[ $dry_run_mode -eq 1 ]]; then
            log dry "Would copy: $src -> ${dest_path}"
            return 0
        fi

        mkdir -p "$(dirname "$final_dest")" 2>/dev/null || true
        if [[ -e $final_dest || -L $final_dest ]]; then
            handle_file_conflict "$final_dest" "$target" || return 0
        fi

        if rsync -a "$src" "$final_dest"; then
            log ok "copied: $(basename "$src") -> $dest_path"
        else
            log error "Failed to copy $src to $final_dest"
            return 1
        fi
    else
        # Relative structure
        if [[ $dry_run_mode -eq 1 ]]; then
            log dry "Would copy with relative structure: $(basename "$src") -> $target/"
            return 0
        fi

        if (cd "$(dirname "$src")" && rsync -a --relative "./$(basename "$src")" "$target/"); then
            log ok "copied: $(basename "$src")"
        else
            log error "Failed to copy $src with relative structure"
            return 1
        fi
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

        local matching_files
        matching_files="$(find_matching_files "$pattern" "$source_root")"

        if [[ -z $matching_files ]]; then
            log verb "skip (missing): $pattern"
            continue
        fi

        log verb "Found matches for '$pattern': $(echo "$matching_files" | wc -l) files"

        while IFS= read -r src_file; do
            [[ -z $src_file ]] && continue
            [[ -e $source_root/$src_file || -L $source_root/$src_file ]] || { log warn "skip (missing): $src_file"; continue; }

            if [[ -n $dest_override && $dest_override != "$pattern" ]]; then
                copy_file "$source_root/$src_file" "$target" "$dest_override"
            else
                copy_file "$source_root/$src_file" "$target"
            fi
        done <<< "$matching_files"
    done
}

process_config_file() {
    local target="$1" config_file="$2"

    while IFS= read -r line || [[ -n $line ]]; do
        local -a rule_parts=()
        parse_config_rule "$line" rule_parts || continue

        local src_pattern="${rule_parts[0]}" dest_rel="${rule_parts[1]}"
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

        if [[ ! -d $target_path ]]; then
            log warn "Target directory does not exist: $target_path"
            continue
        fi

        log info "Copying files into: $target_path"
        copy_into_target "$target_path"
    done
}

# ========== MAIN EXECUTION ==========
process_targets
log ok "Done."
