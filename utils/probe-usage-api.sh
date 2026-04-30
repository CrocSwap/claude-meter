#!/usr/bin/env bash
# probe-usage-api.sh — verify that GET /api/oauth/usage still works and
# inspect the response shape.
#
# Two token sources, in order:
#   1. $CLAUDE_TOKEN  (preferred once claude-meter has its own OAuth)
#   2. Decrypt one out of Claude desktop's local token cache via the
#      sibling extract-claude-desktop-token.py helper.
#
# Output goes to stdout (pretty-printed JSON) and to OUT_PATH.

set -euo pipefail

OUT_PATH="${OUT_PATH:-/tmp/claude-meter-usage-probe.json}"
HERE="$(cd "$(dirname "$0")" && pwd)"

if [[ -n "${CLAUDE_TOKEN:-}" ]]; then
    TOKEN="$CLAUDE_TOKEN"
else
    echo "No \$CLAUDE_TOKEN; falling back to Claude desktop token cache." >&2
    export _PW="$(security find-generic-password -s "Claude Safe Storage" -a "Claude" -w)"
    export _CONFIG_PATH="$HOME/Library/Application Support/Claude/config.json"
    TOKEN="$(python3 "$HERE/extract-claude-desktop-token.py")"
    unset _PW _CONFIG_PATH
fi

curl -sS \
    -H "Accept: application/json, text/plain, */*" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "User-Agent: claude-meter-probe/0.0 (macOS)" \
    "https://api.anthropic.com/api/oauth/usage" \
    | python3 -m json.tool > "$OUT_PATH"

cat "$OUT_PATH"
echo
echo "Saved to $OUT_PATH"
