# copy-configs

Universal configuration file copying utility for git repositories. Safely copies predefined files and directories from a source repository to target locations while preserving relative paths.

**Built on top of [gwq](https://github.com/d-kuro/gwq) - the powerful Git Worktree Manager that revolutionizes parallel development workflows.**

## Why copy-configs?

When working with git worktrees, you often encounter a frustrating problem: **git-tracked files are copied to the new worktree, but untracked files are not**. This means essential development files like:

- Environment variables (`.env*` files)
- IDE configurations (`.vscode/settings.json`)
- LLM Rules (`CLAUDE.md`, `.cursor/`)
- Local configuration files

...are missing from your new worktree, forcing you to manually copy them every time. This disrupts your development workflow and leads to inconsistent environments across worktrees.

**copy-configs solves this problem** by automatically copying these essential untracked files to new worktrees, ensuring every worktree has the complete development environment you need to be productive immediately.

## What is gwq?

[gwq](https://github.com/d-kuro/gwq) is a powerful CLI tool for efficiently managing Git worktrees, similar to how `ghq` manages repository clones. It provides intuitive operations for creating, switching, and deleting worktrees using a fuzzy finder interface.

### Key gwq Features:

- **Fuzzy Finder Interface**: Intuitive branch and worktree selection
- **Global Worktree Management**: Access all worktrees across repositories
- **Parallel AI Development**: Enable multiple AI agents to work simultaneously
- **Status Dashboard**: Monitor all worktrees' activity at a glance
- **Smart Directory Organization**: URL-based hierarchy preventing naming conflicts

**copy-configs enhances gwq** by solving the untracked file problem - the missing piece that makes worktree workflows truly seamless.

## Features

- Copy configuration files (`.env*`, `CLAUDE.md`, `.cursor/`, `.vscode/settings.json`) by default
- Custom configuration rules via `.copyconfigs` file
- Multiple input methods: stdin, file, or command-line arguments
- Conflict handling: skip, overwrite, or backup existing files
- Path safety validation to prevent traversal attacks
- Dry-run mode to preview operations
- Comprehensive logging with color support

## Installation

### Quick Install (Recommended)

Install both `gwq` and `copy-configs` automatically:

```bash
curl -fsSL https://raw.githubusercontent.com/gapurov/copy-configs/refs/heads/main/install.sh | bash
```

This script will:

- Download and install the latest `gwq` binary for your platform
- Download and install the `copy-configs` scripts
- Set up convenient symlinks for easy access
- Provide PATH configuration instructions

### Manual Installation

1. Install [gwq](https://github.com/d-kuro/gwq) (required for `gwq-addx.sh`)
2. Clone or download the scripts to your desired location
3. Make them executable:
   ```bash
   chmod +x copy-configs.sh gwq-addx.sh
   ```

## Requirements

- git
- rsync
- For `gwq-addx.sh`: gwq, jq

## Usage

### Basic Usage

```bash
# Copy to a single target directory
echo "/path/to/target" | copy-configs.sh

# Copy to multiple directories from file
copy-configs.sh < target_paths.txt

# Direct command-line target
copy-configs.sh --target /path/to/target

# Multiple targets
copy-configs.sh -t /path/to/dir1 -t /path/to/dir2
```

### Options

- `--config, -c FILE` - Path to custom config file
- `--conflict, -C MODE` - Conflict handling: `skip`|`overwrite`|`backup` (default: skip)
- `--target, -t PATH` - Explicit target path (can be repeated)
- `--no-color` - Disable ANSI colors
- `--verbose, -v` - Enable verbose output
- `--debug` - Enable debug output
- `--dry-run, -n` - Show what would be done without executing
- `--help, -h` - Show help

### Configuration

Create a `.copyconfigs` file in your repository root to define custom copy rules:

```
# Format: source_pattern[:destination_path]
.env*
CLAUDE.md
.cursor/
.vscode/settings.json
config/database.yml:config/database.yml.example
```

You can specify the config globally in either of the following locations:

1. Explicit `--config` argument
2. `~/.config/copy-configs/config`
3. `~/.config/gwq/copyconfigs`

### gwq-addx: Enhanced Worktree Creation

`gwq-addx.sh` is a **complete wrapper around `gwq add`** that adds automatic file copying functionality.

**🔄 Full gwq add Compatibility**: `gwq-addx` supports **everything** that `gwq add` supports - it simply passes all arguments through to `gwq add` after handling its own copy-configs options.

**This means you can use `gwq-addx` as a drop-in replacement for `gwq add` with added file automation:**

```bash
# Create worktree and copy files automatically
gwq-addx -b feature/new-feature

# The workflow:
# 1. Creates a new worktree using gwq
# 2. Automatically detects the new worktree path
# 3. Copies your .env files, IDE configs, and other essentials
# 4. You're ready to code immediately!

# With custom config for specific file patterns
gwq-addx --config ./custom.copyconfigs -b feature/api

# Preview what would be copied without creating the worktree
gwq-addx --dry-run -b feature/test
```

#### Complete gwq add Support

Since `gwq-addx` is a wrapper, it supports **all gwq add functionality**:

```bash
# All standard gwq add commands work with gwq-addx:

# Create worktree with new branch (+ auto file copying)
gwq-addx -b feature/new-ui

# Create from existing branch (+ auto file copying)
gwq-addx main

# Create at specific path with new branch (+ auto file copying)
gwq-addx -b feature/new-ui ~/projects/myapp-feature

# Create from remote branch (+ auto file copying)
gwq-addx -b feature/api-v2 origin/feature/api-v2

# Interactive branch selection with fuzzy finder (+ auto file copying)
gwq-addx -i

# Any other gwq add options work exactly the same:
gwq-addx --help                    # Shows gwq add help + copy-configs options
gwq-addx -b feat/x --track origin  # All gwq add flags are supported
```

**How it works:**

1. `gwq-addx` processes its own options (`--config`, `--conflict`, `--verbose`, etc.)
2. Passes all remaining arguments directly to `gwq add`
3. Detects newly created worktrees automatically
4. Copies files using copy-configs to the new worktrees

**Copy-configs specific options** (handled by gwq-addx):

- `--config, -c FILE` - Custom copy rules file
- `--conflict, -C MODE` - File conflict handling (skip/overwrite/backup)
- `--verbose, -v` - Verbose copy operation output
- `--debug` - Debug copy operations
- `--dry-run, -n` - Preview file operations
- `--no-color` - Disable colored output

**All other options** are passed through to `gwq add` unchanged.

**Before copy-configs (using gwq alone):**

```bash
gwq add -b feature/auth          # gwq creates worktree (git-tracked files only)
cd path/to/new/worktree         # Navigate to worktree
cp ../.env* .                   # Manual copy - tedious!
cp -r ../.cursor .              # More manual copying...
cp ../CLAUDE.md .               # Even more copying...
```

**With copy-configs + gwq:**

```bash
gwq-addx -b feature/auth        # gwq creates worktree + copy-configs handles files
cd path/to/new/worktree         # Ready to work immediately!
```

**The perfect combination**: gwq's powerful worktree management + copy-configs' automatic file handling = seamless development workflow.

#### Drop-in Replacement Summary

Replace `gwq add` with `gwq-addx` in your workflow to get automatic file copying:

| Old Command               | New Command                | Result                                   |
| ------------------------- | -------------------------- | ---------------------------------------- |
| `gwq add -b feature/auth` | `gwq-addx -b feature/auth` | Same worktree + auto-copied files        |
| `gwq add main`            | `gwq-addx main`            | Same worktree + auto-copied files        |
| `gwq add -i`              | `gwq-addx -i`              | Same fuzzy selection + auto-copied files |
| `gwq add origin/develop`  | `gwq-addx origin/develop`  | Same remote branch + auto-copied files   |

**Key Benefits:**

- ✅ **Zero learning curve** - same commands, enhanced functionality
- ✅ **All gwq add features preserved** - nothing is lost
- ✅ **Automatic file copying added** - no manual copying needed
- ✅ **Configurable** - customize which files to copy

## Security

- Validates paths to prevent directory traversal attacks
- Rejects absolute paths and home directory references in config
- Limits configuration file size (1MB max)
- Sanitizes input for control characters

## Examples

### Worktree Workflows

```bash
# Quick worktree creation with file copying
gwq-addx -b feature/user-auth

# Start a hotfix worktree
gwq-addx -b hotfix/security-patch

# Create worktree from existing branch
gwq-addx main

# Verbose output to see what's being copied
gwq-addx --verbose -b feature/new-api
```

### Standalone File Copying

```bash
# Copy files to any directory
echo "/tmp/my-project" | copy-configs.sh

# Copy to multiple directories
copy-configs.sh -t /path/to/project1 -t /path/to/project2

# Backup existing files instead of skipping
copy-configs.sh --conflict backup --target /path/to/project

# Preview what would be copied
copy-configs.sh --dry-run --target /path/to/project
```

### Custom Configuration

```bash
# Use custom copy rules
gwq-addx --config ./deploy.copyconfigs -b deploy/staging

# Debug mode to see detailed operations
copy-configs.sh --debug --target /path/to/project
```

### Advanced gwq + copy-configs Workflows

These examples leverage gwq's advanced features combined with copy-configs:

```bash
# Parallel AI Development (gwq's killer feature + copy-configs)
gwq-addx -b feature/auth        # AI agent 1 works on authentication
gwq-addx -b feature/api         # AI agent 2 works on API
gwq-addx -b feature/ui          # AI agent 3 works on UI

# Each worktree has complete dev environment thanks to copy-configs
# Monitor all AI agent activity with gwq's status dashboard
gwq status --watch

# Use gwq's global worktree management
gwq list -g                     # See all worktrees across projects
gwq exec -g myapp:feature -- npm test  # Run tests in any worktree

# Leverage gwq's tmux integration for long-running tasks
gwq tmux run --id dev-server "npm run dev"
gwq tmux run --id test-watch "npm run test:watch"

# gwq's fuzzy finder with copy-configs automation
gwq-addx -i                     # Interactive branch selection
```

**Why this combination is powerful:**

- **gwq** provides the foundation: intelligent worktree management, fuzzy selection, global access, tmux integration
- **copy-configs** fills the gap: ensures every worktree has complete development environment
- **Together** they enable truly seamless parallel development workflows

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Author

Enhanced with Claude Code assistance for performance and reliability.
