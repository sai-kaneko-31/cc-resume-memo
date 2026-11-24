#!/usr/bin/env bash
# Fixture: a known-issues directory that holds one note written by hand. It has no "rule:" first
# line, so it is not an entry. It already says what the recap of the case reports.
set -euo pipefail

mkdir -p out/known-issues
cat > out/known-issues/shell-notes.md <<'EOF'
# Known issues: shell

## `rg -h` prints the help, not the matches

case: `rg -h 'x' dir` printed the help text and no matches. In ripgrep, `-h` is `--help`.

prevention: hide the file names with `-I` (`--no-filename`).
EOF
