# copy-configs

Automatically copy untracked files (`.env*`, AI configs, IDE settings) to new git worktrees.

**Built on [gwq](https://github.com/d-kuro/gwq) - the powerful Git Worktree Manager.**

Now with native `gwq addx` integration!

## What is gwq?

[gwq](https://github.com/d-kuro/gwq) is a CLI tool for efficiently managing Git worktrees with a fuzzy finder interface. Key features:

- **Fuzzy Finder Interface** - Intuitive branch and worktree selection
- **Global Worktree Management** - Access all worktrees across repositories  
- **Parallel AI Development** - Enable multiple AI agents to work simultaneously
- **Status Dashboard** - Monitor all worktrees' activity at a glance
- **Smart Directory Organization** - URL-based hierarchy preventing naming conflicts

**copy-configs enhances gwq** by solving the untracked file problem - the missing piece for seamless worktree workflows. Use `gwq addx` for natural integration!

## Why copy-configs?

When working with git worktrees, you encounter a frustrating problem: **git worktrees only copy tracked files**. Essential untracked development files are missing from new worktrees:

- Environment variables (`.env*` files)
- AI/LLM configurations (`CLAUDE.md`, `GEMINI.md`, `AGENTS.md`, `.claude/`, `.clinerules/`)
- IDE settings (`.cursor/`, `.augment/`, `.vscode/settings.json`)
- Local configuration files

This forces you to manually copy these files every time you create a worktree, disrupting your workflow.

**copy-configs solves this** by automatically copying these essential files to new worktrees, ensuring every worktree has a complete development environment immediately.

### Default Files Copied

copy-configs automatically copies these files when no custom config is specified:
- `.env*` - Environment variables
- `CLAUDE.md`, `GEMINI.md`, `AGENTS.md` - AI assistant configurations  
- `.claude/`, `.clinerules/` - AI-specific directories
- `.cursor/`, `.augment/` - Modern IDE configurations
- `.vscode/settings.json` - VS Code settings

## Installation

### Quick Install (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/gapurov/copy-configs/refs/heads/main/install.sh | bash
```

This script will:
- Download and install the latest `gwq` binary for your platform
- Download and install the `copy-configs` scripts
- Set up convenient symlinks for easy access
- Provide PATH configuration instructions

### Manual Installation

1. Install [gwq](https://github.com/d-kuro/gwq) (required for `gwq addx`)
2. Clone or download the scripts to your desired location
3. Make them executable:
   ```bash
   chmod +x copy-configs.sh gwqx
   ```

## Usage

### gwq addx (Native Integration)

**New!** copy-configs now integrates natively with gwq as the `addx` subcommand.

Simply use `gwq addx` instead of `gwq add` for enhanced worktree creation:

```bash
# Instead of: gwq add -b feature/auth
gwq addx -b feature/auth    # Creates worktree + copies files automatically

# All gwq add options work exactly the same:
gwq addx -i                 # Interactive branch selection
gwq addx main               # From existing branch  
gwq addx origin/develop     # From remote branch
gwq addx -b feat --config ./custom.copyconfigs  # Custom file patterns
```

**The workflow improvement:**
- **Before**: `gwq add` → `cd worktree` → manually copy `.env*`, AI configs, IDE settings → start coding
- **After**: `gwq addx` → `cd worktree` → start coding immediately

### Alternative Usage

You can also use gwqx directly:

```bash
gwqx -b feature/auth        # Direct gwqx command
```

#### gwq addx Options

**Copy-configs specific options:**
- `--config, -c FILE` - Custom copy rules file
- `--conflict, -C MODE` - File conflict handling: `skip`|`overwrite`|`backup` (default: skip)
- `--verbose, -v` - Verbose copy operation output
- `--debug` - Debug copy operations
- `--dry-run, -n` - Preview file operations without creating worktree
- `--no-color` - Disable colored output

**All other options** are passed through to `gwq add` unchanged (see `gwq add --help`).

#### Drop-in Replacement

Replace `gwq add` with `gwq addx` in your workflow:

| Old Command | New Command | Result |
|-------------|-------------|---------|
| `gwq add -b feature/auth` | `gwq addx -b feature/auth` | Same worktree + auto-copied files |
| `gwq add main` | `gwq addx main` | Same worktree + auto-copied files |
| `gwq add -i` | `gwq addx -i` | Same fuzzy selection + auto-copied files |
| `gwq add origin/develop` | `gwq addx origin/develop` | Same remote branch + auto-copied files |

### Standalone Usage

Use `copy-configs.sh` directly for copying files to any directory:

```bash
# Copy to single directory
echo "/path/to/target" | copy-configs.sh
copy-configs.sh --target /path/to/project

# Copy to multiple directories
copy-configs.sh -t /path/to/dir1 -t /path/to/dir2
copy-configs.sh < target_paths.txt
```

#### Standalone Options

- `--config, -c FILE` - Path to custom config file
- `--conflict, -C MODE` - Conflict handling: `skip`|`overwrite`|`backup` (default: skip)
- `--target, -t PATH` - Explicit target path (can be repeated)
- `--verbose, -v` - Enable verbose output
- `--debug` - Enable debug output  
- `--dry-run, -n` - Show what would be done without executing
- `--no-color` - Disable ANSI colors
- `--help, -h` - Show help

## Configuration

Optional `.copyconfigs` file in your repo:

```
.env*
CLAUDE.md
GEMINI.md
.claude/
.cursor/
custom-config.json
```

## Examples

```bash
# Enhanced worktree workflow with native integration
gwq addx -b feature/auth --verbose
gwq addx --config ./deploy.copyconfigs -b staging

# Direct gwqx usage
gwqx -b feature/auth --verbose
gwqx --config ./deploy.copyconfigs -b staging

# Standalone copying  
copy-configs.sh --dry-run --target /tmp/project
copy-configs.sh --conflict backup -t /path1 -t /path2
```

## Requirements

- `git`, `rsync` 
- For `gwq addx`: `gwq`, `jq`

## License

MIT - see [LICENSE](LICENSE) file.