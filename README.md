# copy-configs

Automatically copy untracked files (`.env*`, AI configs, IDE settings) to new git worktrees.

## Problem

When working with git worktrees, you encounter a frustrating problem: **git worktrees only copy tracked files**. Essential untracked development files are missing from new worktrees:

- Environment variables (`.env*` files)
- AI/LLM configurations (`CLAUDE.md`, `GEMINI.md`, `AGENTS.md`, `.claude/`, `.clinerules/`)
- IDE settings (`.cursor/`, `.augment/`, `.vscode/settings.json`)
- Local configuration files

This forces you to manually copy these files every time you create a worktree, disrupting your workflow.

copy-configs solves this by automatically copying these files when creating new worktrees with [gwq](https://github.com/d-kuro/gwq).

## Installation

### 1. Install `gwq` (dependency)

```bash
mkdir -p ~/.local/share ~/.local/bin && git clone https://github.com/d-kuro/gwq.git ~/.local/share/gwq && (cd ~/.local/share/gwq && go build -o ~/.local/bin/gwq ./cmd/gwq)
```

This clones the upstream repository and builds the latest binary into `~/.local/bin/gwq` (adjust paths if you prefer a different location).

### 2. Install copy-configs helpers + alias

```bash
mkdir -p ~/.local/share && git clone https://github.com/gapurov/copy-configs.git ~/.local/share/copy-configs && alias gwq=~/.local/share/copy-configs/gwqx
```

Prefer curl only?

```bash
mkdir -p ~/.local/bin && curl -fsSL https://raw.githubusercontent.com/gapurov/copy-configs/main/gwqx -o ~/.local/bin/gwqx && curl -fsSL https://raw.githubusercontent.com/gapurov/copy-configs/main/copy-configs.sh -o ~/.local/bin/copy-configs.sh && chmod +x ~/.local/bin/gwqx ~/.local/bin/copy-configs.sh && alias gwq=~/.local/bin/gwqx
```

Append the alias (`alias gwq=...`) to your shell profile (e.g. `~/.bashrc`, `~/.zshrc`) so it persists across sessions. After setup, run `copy-configs.sh --help` to review available flags.

## Usage

Use `gwq addx` instead of `gwq add` to create worktrees with files automatically copied:

```bash
gwq addx -b feature/auth    # Creates worktree + copies files
gwq addx -i                 # Interactive selection
gwq addx main               # From existing branch
```

### Options

- `--config, -c FILE` - Custom copy rules file
- `--conflict, -C MODE` - Handle conflicts: `skip`|`overwrite`|`backup` (default: skip)
- `--verbose, -v` - Verbose output
- `--dry-run, -n` - Preview without creating
- `--version` - Print the installed gwqx and copy-configs versions

All other `gwq add` options work the same.

### Default Files Copied

When no `.copyconfigs` file exists, these files are automatically copied:

- `.env*` - Environment variables
- `CLAUDE.md`, `GEMINI.md`, `AGENTS.md` - AI assistant configurations
- `.claude/`, `.clinerules/` - AI-specific directories
- `.cursor/`, `.augment/` - Modern IDE configurations
- `.vscode/settings.json` - VS Code settings

## Configuration

Create `.copyconfigs` in your repo to customize which files are copied:

```
.env*
CLAUDE.md
.claude/
.cursor/
custom-config.json
```

Without this file, default patterns are used (`.env*`, AI configs, IDE settings).

## Requirements

- `git`, `rsync`, `gwq`, `jq`

## License

MIT
