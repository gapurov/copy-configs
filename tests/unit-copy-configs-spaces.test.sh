#!/usr/bin/env bash

set -euo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SCRIPT_PATH="$PROJECT_ROOT/copy-configs.sh"

readonly TEMP_SOURCE="$(mktemp -d)"
readonly TEMP_TARGET="$(mktemp -d)"

cleanup() {
    rm -rf "$TEMP_SOURCE" "$TEMP_TARGET"
}

trap cleanup EXIT

mkdir -p "$TEMP_SOURCE/agents"
cat <<'EOF' > "$TEMP_SOURCE/agents/My Agent.json"
{}
EOF

cat <<'EOF' > "$TEMP_SOURCE/.copyconfigs"
agents/My Agent.json
EOF

if ! "$SCRIPT_PATH" --source "$TEMP_SOURCE" --target "$TEMP_TARGET" >/dev/null; then
    echo "FAIL copy-configs execution" >&2
    exit 1
fi

if [[ ! -f "$TEMP_TARGET/agents/My Agent.json" ]]; then
    echo "FAIL missing copied file with spaces" >&2
    exit 1
fi

echo "PASS copy-configs handles filenames with spaces"
