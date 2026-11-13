#!/usr/bin/env bash
# PreCompact hook. Claude Code uses a PreCompact hook's stdout as instructions
# for the compaction summary (hooks reference, "PreCompact output"; at most
# 10,000 characters per hook).
set -u

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib-find-memos.sh
. "$here/lib-find-memos.sh"

[ -t 0 ] || cat >/dev/null

project=$(resume_memo_project "${CLAUDE_PROJECT_DIR:-$PWD}")
latest=$(resume_memo_open_memos "$project" | tail -n 1)

cat <<'EOF'
In the summary, keep what exists only in the conversation, in this priority order:
- Decisions agreed with the user, and the reasons ("why B and not A").
- Approaches that were tried and failed, and why they failed.
- Observations (commands run, their output, real API behaviour), kept apart from the explanations inferred from them. Mark an inference drawn from a single observation as unverified.
- Open questions and items waiting for the user.
- The next steps in work order, and the active branch, worktree path and PR number.
Quote verbatim: IDs, URLs, file paths, line numbers, error messages, commands, table and column names.
Do not copy file contents or diffs; give the path and line instead.
EOF

if [ -n "$latest" ]; then
  echo "A resume memo for this project is open: $latest"
  echo "Put that path in the summary."
fi
