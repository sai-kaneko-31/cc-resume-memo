#!/usr/bin/env bash
# Fixture: a memo directory (out) that already has one known issue about a plain list item that contains ": ".
set -euo pipefail

mkdir -p out/known-issues
cat > out/known-issues/colon-in-plain-item.md <<'EOF'
rule: Write a list item that contains ": " as a "- |" block scalar from the start
count: 1
first_seen: 2026-11-20
last_seen: 2026-11-20
case: the check exited 1 with `next[0] is Hash, not a string` because the step `run: the migration` was a plain list item
prevention: start any step that contains ": " with "- |" instead of rewriting it after the check fails
EOF
