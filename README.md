# copy-configs

Universal configuration file copying utility for git repositories. Safely copies predefined files and directories from a source repository to target locations while preserving relative paths.

## Features

- Copy configuration files (`.env*`, `CLAUDE.md`, `.cursor/`, `.vscode/settings.json`) by default
- Custom configuration rules via `.copyconfigs` file
- Multiple input methods: stdin, file, or command-line arguments
- Conflict handling: skip, overwrite, or backup existing files
- Path safety validation to prevent traversal attacks
- Dry-run mode to preview operations
- Comprehensive logging with color support

## Installation

1. Clone or download the scripts to your desired location
2. Make them executable:
   ```bash
   chmod +x copy-configs.sh gwq-addx.sh
   ```

## Requirements

- bash 4.0+
- git
- rsync
- timeout (optional)
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

- `--config, -c FILE` - Path to custom rules file
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

Configuration file search order:
1. Explicit `--config` argument
2. `$PWD/.copyconfigs`
3. `$HOME/.config/copy-configs/config`
4. `$HOME/.config/gwq/copyconfigs`

### gwq-addx Integration

`gwq-addx.sh` wraps `gwq add` to automatically copy files to new worktrees:

```bash
# Create worktree and copy files
gwq-addx -b feature/new-feature

# With custom config
gwq-addx --config ./custom.copyconfigs -b feature/api

# Dry run
gwq-addx --dry-run -b feature/test
```

## Security

- Validates paths to prevent directory traversal attacks
- Rejects absolute paths and home directory references in config
- Limits configuration file size (1MB max)
- Sanitizes input for control characters

## Examples

```bash
# Basic usage with default patterns
echo "/tmp/my-project" | copy-configs.sh

# Verbose mode with custom conflict handling
copy-configs.sh --verbose --conflict backup --target /path/to/project

# Dry run to see what would be copied
copy-configs.sh --dry-run --target /path/to/project

# Using gwq-addx for worktree creation
gwq-addx --verbose -b feature/authentication
```

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Author

Enhanced with Claude Code assistance for performance and reliability.