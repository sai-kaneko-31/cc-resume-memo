# shellcheck shell=bash
# Helpers shared by the resume-memo hooks. Source this file; do not execute it.

# Directory that holds the memos. RESUME_MEMO_DIR overrides the default.
resume_memo_dir() {
  printf '%s\n' "${RESUME_MEMO_DIR:-$HOME/.claude/resume-memos}"
}

# Name of the project that a directory belongs to: the main checkout's
# directory name inside a git repository (a worktree resolves to its main
# checkout), otherwise the directory's own name.
resume_memo_project() {
  local dir="${1:-$PWD}" common
  if common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
    basename "$(dirname "$common")"
  else
    basename "$dir"
  fi
}

# Path of the archive that belongs to memo $1: the same file name in a "done"
# directory next to the memo. The memo glob below does not recurse, so it never
# lists an archive. The archive may not exist.
resume_memo_archive_path() {
  printf '%s/done/%s\n' "$(dirname "$1")" "$(basename "$1")"
}

# Print the paths of the memos of project $1 that have "status: open", oldest
# first. File names start with a timestamp, so name order is time order.
resume_memo_open_memos() {
  local project="$1" dir f
  dir=$(resume_memo_dir)
  [ -d "$dir" ] || return 0
  for f in "$dir"/*-"$project"-*.yml; do
    [ -f "$f" ] || continue
    if grep -q '^status: open[[:space:]]*$' "$f"; then
      printf '%s\n' "$f"
    fi
  done
}
