#!/usr/bin/env bash
# A small log of failures that happened while the resume-memo skill ran, so the
# next run can avoid them. One file per entry, in a "known-issues" directory
# inside the memo directory: <memo dir>/known-issues/<slug>.md
#
#   known-issue.sh list [--max N]       one line per entry, most repeated first (default N = 20)
#   known-issue.sh add <slug>           create an entry from stdin; see "Entry" below
#   known-issue.sh recur <slug> <note>  count another occurrence of an existing entry
#
# Entry (the text on stdin for "add"): a first line "rule: <one line, at most
# 200 characters>", then a "case:" line and a "prevention:" line, then any other
# text. The script adds the "count:", "first_seen:" and "last_seen:" lines
# after the rule, and "recur" appends a "recurrence: <date>: <note>" line.
#
# Exit codes
#   0   done
#   1   no temporary directory could be made under TMPDIR (default /tmp)
#   2   secret-like text found, nothing was written (the output names the pattern and the line)
#   4   add: an entry with this slug already exists (use "recur")
#   5   recur: no entry with this slug
#   64  usage error, or an entry that does not have the required lines
#
# Environment
#   RESUME_MEMO_DIR    memo directory, the same variable the other scripts read
#   RESUME_MEMO_TODAY  date to write instead of today (YYYY-MM-DD), mainly for the tests

set -u

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib-find-memos.sh
. "$here/lib-find-memos.sh"

issues_dir="$(resume_memo_dir)/known-issues"
today="${RESUME_MEMO_TODAY:-$(date +%Y-%m-%d)}"
max_rule=200
cap_note=30

# The temporary directory is made when a command first needs it. The template
# names TMPDIR: macOS "mktemp -d" without a template ignores TMPDIR, and fails
# where only TMPDIR is writable (a sandbox).
tmp=""
trap '[ -z "$tmp" ] || rm -rf "$tmp"' EXIT
make_tmp() {
  [ -z "$tmp" ] || return 0
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/known-issue.XXXXXX") || {
    tmp=""
    echo "known-issue.sh: cannot create a temporary directory under ${TMPDIR:-/tmp}. Set TMPDIR to a writable directory." >&2
    exit 1
  }
}

usage() {
  cat >&2 <<'EOF'
usage: known-issue.sh list [--max N]
       known-issue.sh add <slug>            (entry text on stdin: rule:, case:, prevention: lines)
       known-issue.sh recur <slug> <note>
EOF
  exit 64
}

valid_slug() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]]
}

# Scan a file for secret-like text with the memo checker. On a hit, print the
# pattern and line (never the value) and exit 2.
scan_or_exit() {
  local out
  if ! out=$("$here/check-memo.sh" --secrets-only "$1" 2>&1); then
    printf '%s\n' "$out" >&2
    echo "known-issue.sh: nothing was written. Remove the value and keep only its name." >&2
    exit 2
  fi
}

cmd_list() {
  local max=20 f slug rule count last lines total
  if [ "${1:-}" = "--max" ]; then
    max="${2:-}"
    shift 2 2>/dev/null || usage
    [[ "$max" =~ ^[1-9][0-9]*$ ]] || { echo "known-issue.sh: --max needs a positive number" >&2; exit 64; }
  fi
  [ "$#" -eq 0 ] || usage
  [ -d "$issues_dir" ] || exit 0
  ls "$issues_dir"/*.md > /dev/null 2>&1 || exit 0
  make_tmp

  : > "$tmp/rows"
  for f in "$issues_dir"/*.md; do
    [ -f "$f" ] || continue
    slug=$(basename "$f" .md | tr -d '\000-\037')
    rule=$(grep -m 1 '^rule: ' "$f" | sed 's/^rule: //' | tr -d '\000-\010\013-\037' | cut -c "1-$max_rule")
    count=$(grep -m 1 -E '^count: [0-9]+[[:space:]]*$' "$f" | sed 's/^count: //; s/[[:space:]]*$//')
    last=$(grep -m 1 -E '^last_seen: [0-9-]+[[:space:]]*$' "$f" | sed 's/^last_seen: //; s/[[:space:]]*$//')
    printf '%s\t%s\t%s\t%s\n' "${count:-1}" "${last:--}" "$slug" "$rule" >> "$tmp/rows"
  done
  total=$(wc -l < "$tmp/rows" | tr -d ' ')
  [ "$total" -gt 0 ] || exit 0

  sort -t "$(printf '\t')" -k1,1nr -k2,2r -k3,3 "$tmp/rows" > "$tmp/sorted"
  head -n "$max" "$tmp/sorted" | while IFS="$(printf '\t')" read -r count last slug rule; do
    printf '%s x%s %s: %s\n' "$slug" "$count" "$last" "$rule"
  done
  if [ "$total" -gt "$max" ]; then
    lines=$((total - max))
    echo "(+$lines more: ls $issues_dir)"
  fi
}

cmd_add() {
  local slug="${1:-}" rule target n
  valid_slug "$slug" || { echo "known-issue.sh: the slug must be lowercase letters, digits and hyphens (at most 64 characters)" >&2; exit 64; }
  [ "$#" -eq 1 ] || usage
  make_tmp
  cat > "$tmp/entry"

  rule=$(sed -n 1p "$tmp/entry")
  case "$rule" in
    "rule: "?*) rule="${rule#rule: }" ;;
    *) echo "known-issue.sh: the first line must be 'rule: <one line>'" >&2; exit 64 ;;
  esac
  if [ "${#rule}" -gt "$max_rule" ]; then
    echo "known-issue.sh: the rule is over $max_rule characters; keep it to one short line" >&2
    exit 64
  fi
  grep -q '^case: ' "$tmp/entry" || { echo "known-issue.sh: the entry needs a 'case:' line" >&2; exit 64; }
  grep -q '^prevention: ' "$tmp/entry" || { echo "known-issue.sh: the entry needs a 'prevention:' line" >&2; exit 64; }
  if grep -q -E '^(count|first_seen|last_seen|recurrence): ' "$tmp/entry"; then
    echo "known-issue.sh: do not write count:, first_seen:, last_seen: or recurrence: lines; the script writes them" >&2
    exit 64
  fi
  scan_or_exit "$tmp/entry"

  target="$issues_dir/$slug.md"
  if [ -e "$target" ]; then
    echo "known-issue.sh: $slug exists. Count a repeat with: known-issue.sh recur $slug \"<note>\"" >&2
    exit 4
  fi
  mkdir -p "$issues_dir"
  {
    printf 'rule: %s\ncount: 1\nfirst_seen: %s\nlast_seen: %s\n' "$rule" "$today" "$today"
    sed 1d "$tmp/entry"
  } > "$tmp/new"
  mv "$tmp/new" "$target"
  echo "$target"

  n=$(find "$issues_dir" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
  if [ "$n" -gt "$cap_note" ]; then
    echo "Note: $n known issues. Delete the entries that now live in your CLAUDE.md or the skill, and the ones that no longer apply."
  fi
}

cmd_recur() {
  local slug="${1:-}" note="${2:-}" target old new need_c=0 need_l=0
  valid_slug "$slug" || { echo "known-issue.sh: the slug must be lowercase letters, digits and hyphens (at most 64 characters)" >&2; exit 64; }
  [ "$#" -eq 2 ] || usage
  case "$note" in
    "") usage ;;
    *$'\n'*) echo "known-issue.sh: the note must be one line" >&2; exit 64 ;;
  esac
  if [ "${#note}" -gt "$max_rule" ]; then
    echo "known-issue.sh: the note is over $max_rule characters; keep it to one short line" >&2
    exit 64
  fi
  target="$issues_dir/$slug.md"
  [ -f "$target" ] || { echo "known-issue.sh: no entry named $slug" >&2; exit 5; }
  make_tmp
  printf '%s\n' "$note" > "$tmp/note"
  scan_or_exit "$tmp/note"

  old=$(grep -m 1 -E '^count: [0-9]+[[:space:]]*$' "$target" | sed 's/^count: //; s/[[:space:]]*$//')
  [ -n "$old" ] || need_c=1
  new=$(( ${old:-1} + 1 ))
  grep -q -E '^last_seen: ' "$target" || need_l=1

  awk -v c="$new" -v d="$today" -v need_c="$need_c" -v need_l="$need_l" '
    NR == 1 { print; if (need_c) print "count: " c; if (need_l) print "last_seen: " d; next }
    /^count: / && !need_c && !hc { print "count: " c; hc = 1; next }
    /^last_seen: / && !need_l && !hl { print "last_seen: " d; hl = 1; next }
    { print }
  ' "$target" > "$tmp/new"
  printf 'recurrence: %s: %s\n' "$today" "$note" >> "$tmp/new"
  mv "$tmp/new" "$target"
  echo "$slug: count $new"
}

command="${1:-}"
[ "$#" -gt 0 ] && shift
case "$command" in
  list) cmd_list "$@" ;;
  add) cmd_add "$@" ;;
  recur) cmd_recur "$@" ;;
  *) usage ;;
esac
