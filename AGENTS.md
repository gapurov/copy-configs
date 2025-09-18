# Repository Guidelines

## Project Structure & Module Organization

- `copy-configs.sh` holds the primary sync logic invoked by `gwq addx`.
- The README documents installation via git clone / curl one-liners; keep those snippets current across macOS, Linux, and WSL.
- `gwqx` extends `gwq` with `addx`; review it when adjusting CLI UX.

## Build, Test, and Development Commands

- `./copy-configs.sh --help` prints runtime options; run this after edits to confirm the flag surface.
- `gwqx addx --help` verifies CLI parsing without creating worktrees (fails fast on parsing issues).
- Manually exercise `gwq addx` inside a throwaway git repo when changing copy logic.

## Coding Style & Naming Conventions

- Shell scripts use Bash with `set -euo pipefail`; preserve that guard in new entry points.
- Indent with four spaces; align continued flags beneath their command for readability.
- Prefer descriptive, uppercase `readonly` constants; reserve lowercase for mutable locals.
- Log helpers emit emoji-like prefixes; reuse `log <level>` to keep output consistent.

## Testing Guidelines

- Add tests only as needed; prefer standalone bash scripts under `tests/` (create the directory if it does not exist).
- Use temporary directories via `mktemp -d` and clean them in traps when possible.
- Validate both success and failure paths by asserting exit codes (`if ! command; then ...`).

## Commit & Pull Request Guidelines

- Follow Conventional Commits (`chore:`, `feat:`, `fix:`) as used in existing history (e.g., `chore: remove unnecessary comments`).
- Scope titles to 70 characters; elaborate in the body with bullet lists when needed.
- PRs should link related issues, note platform coverage (macOS/Linux/WSL), and include manual testing evidence (e.g., `gwqx addx --help`, dry-run walkthrough).

## Security & Configuration Tips

- Never commit `.env*`, AI config folders, or IDE settings; the tool copies them from the source worktree.
- Document custom patterns in `.copyconfigs` so teammates do not hard-code paths in scripts.
- When handling installation, avoid `sudo` unless the destination requires it; offer `--dry-run` guidance for users without elevated access.

## AST‑Grep (Structural Search & Codemods)

- What it is: `ast-grep` is a CLI for structural code search, lint, and safe rewrites using Tree‑sitter ASTs. Think “grep for ASTs,” driven by pattern‑based rules and YAML configs. Command: `sg` (aka `ast-grep`). If `sg` conflicts on your system, use `ast-grep`.

### Core Concepts

- Pattern code: write valid code snippets with meta variables to match structure, not text. Examples: `$VAR` (single node), `$$$ARGS` (zero or more nodes), `$_` (non‑capturing), `$$OP` (unnamed nodes like operators).
- Rules: YAML files combine a `rule` (find), optional `constraints` (filter), `transform` (derive strings), and `fix` (rewrite). Rewriters apply sub‑rules to lists for advanced codemods.
- Safety: interactive diffs with `-i`; apply all with `-U`. Fixes are textual templates; indentation is preserved relative to context.

### Workflow & Safety

- Preview first; never write on the first pass.
  - Ad‑hoc search: `sg run -p 'pattern' src/` (no `-r`) to confirm matches.
  - Rules scan: `sg scan` to preview findings before enabling any fixes.
- Use interactive review to confirm each hunk precisely: add `-i` (`sg run ... -i`, `sg scan -i`).
- Context lines: `-C <N>` shows N lines around matches for safer inspection.
- Only after review, apply changes: use `-U` to apply all confirmed edits.

### Quick Search

- Find console uses in TS:

  `sg run -p "console.log($ARG)" -l ts src/ -C 1`

- Print JSON matches:

  `sg run -p 'fetch($URL)' --json pretty -l ts src/`

### Ad‑Hoc Codemod

- Replace `oldFn(...)` with `newFn(...)` interactively:

  `sg run -p 'oldFn($$$ARGS)' -r 'newFn($$$ARGS)' -l ts -i src/`

- Apply without prompts once reviewed:

  `sg run -p 'oldFn($$$ARGS)' -r 'newFn($$$ARGS)' -l ts -U src/`

### Constraints (Meta Variables + Filters)

- Use constraint matches: combine meta variables ("meta/vars") with filters to tighten scope and avoid false positives.
- Common constraints: `kind`, `has`, `inside`, `not`, `any`, `all`, and metavariable‑level `regex`/`pattern`.

### Tips for Reliable Patterns

- Patterns must be valid code for the target language; when in doubt, use object‑style rules (`kind`, `has`, `inside`, etc.).
- Meta variables are ALL‑CAPS/underscore/digits; do not embed in other tokens. Use `constraints.regex` instead.
- Use `$_` for non‑capturing wildcards and `$$$` for lists of nodes.
- Use `--globs` to scope files; combine with `.gitignore` for noise‑free scans.
- For complex rewrites, prefer YAML `fix` + `transform`/`rewriters` over a long `--rewrite` string.

References: ast‑grep docs (Quick Start, CLI, Pattern Syntax, Lint/Rewrite/Transform/Rewriters, Project Config).
