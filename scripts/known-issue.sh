#!/usr/bin/env bash
# A log of failures, so that a later session can avoid them. One file per entry,
# in one directory: <memo dir>/known-issues by default, or RESUME_MEMO_ISSUES_DIR.
#
#   known-issue.sh list [--max N]       one line per entry, most repeated first (default N = 20)
#   known-issue.sh search <word>...     matching lines of the .md files in the directory
#   known-issue.sh add <slug>           create an entry from stdin; see "Entry" below
#   known-issue.sh recur <slug> <note>  count another occurrence of an existing entry
#   known-issue.sh dir                  print the directory
#
# Entry (the text on stdin for "add"): a first line "rule: <one line, at most
# 200 characters>", then a "case:" line and a "prevention:" line, then any other
# text. The script adds the "count:", "first_seen:" and "last_seen:" lines
# after the rule, and "recur" appends a "recurrence: <date>: <note>" line.
#
# An entry is a regular file whose first line starts with "rule: ". The directory
# may also hold files that someone wrote by hand (notes by area, archives). They
# are not entries: "list" skips them, "search" reads them, and "add" and "recur"
# never change them. A symbolic link is not an entry, and "add" and "recur" never
# write through or replace one.
#
# "search" prints "path:line:text" for every line of every .md file under the
# directory (subdirectories too, and not a symbolic link inside it) that contains
# one of the words, ignoring case.
# It prints at most 20 lines and then "(+N more matching lines)", and nothing when
# no line matches. It exits 0 when it read everything, so an empty output with
# exit 0 means that nothing matched, and 1 when part of the directory was not readable.
#
# Locale: the filters that read a file run in the C locale, so a file that is not
# valid UTF-8 is read like any other. The caps count characters in a UTF-8 locale and
# bytes in the C locale: "add" refuses a rule of more than 200 bytes there, and
# "list" cuts a rule at 200 bytes, which can fall inside a character of a rule
# that was written in a UTF-8 locale. "search" folds the case of ASCII letters only.
#
# Exit codes
#   0   done
#   1   a temporary directory could not be made under TMPDIR (default /tmp), the
#       entry could not be written, the secret scan could not run, or "search"
#       could not read part of the directory
#   2   secret-like text found, nothing was written (the output names the pattern and the line)
#   4   add: a file with this slug already exists. The message says whether it is
#       an entry (use "recur"), a symbolic link or another file (choose another slug)
#   5   recur: no entry with this slug (a file that is not an entry, and a symbolic
#       link, count as none)
#   64  usage error, an entry that does not have the required lines, recur: a
#       count: line of more than 15 digits (leading zeros not counted), or a RESUME_MEMO_ISSUES_DIR that starts
#       with ~name, or with ~ while HOME is empty. Every command exits 64 for the
#       setting, before it does anything else.
#
# Environment
#   RESUME_MEMO_ISSUES_DIR  directory of the entries. A leading ~ or ~/ is expanded with
#                           HOME; ~name is refused. Empty or unset: <memo dir>/known-issues
#   RESUME_MEMO_DIR         memo directory, the same variable the other scripts read
#   RESUME_MEMO_TODAY       date to write instead of today (YYYY-MM-DD), mainly for the tests

set -u

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib-find-memos.sh
. "$here/lib-find-memos.sh"

# The directory of the entries. A settings file that sets the variable may not
# expand a leading ~, so it is expanded here. "~name/x" is not a home directory
# of this process, and as a relative path it would create a directory named "~name".
resolve_issues_dir() {
  local d="${RESUME_MEMO_ISSUES_DIR:-}"
  if [ -z "$d" ]; then
    printf '%s\n' "$(resume_memo_dir)/known-issues"
    return 0
  fi
  # shellcheck disable=SC2088  # the patterns are a literal "~", not a home directory
  case "$d" in
    "~"|"~/"*)
      if [ -z "${HOME:-}" ]; then
        echo "known-issue.sh: RESUME_MEMO_ISSUES_DIR ($d) starts with ~ but HOME is not set. Write the full path." >&2
        return 1
      fi
      d="${HOME%/}${d#\~}"
      [ -n "$d" ] || d=/
      ;;
    "~"*)
      echo "known-issue.sh: RESUME_MEMO_ISSUES_DIR ($d) starts with ~ and a user name. Only ~ and ~/ are expanded, so write the full path." >&2
      return 1
      ;;
  esac
  # A trailing slash would double up in the paths that "search" prints.
  while [ "${#d}" -gt 1 ] && [ "${d%/}" != "$d" ]; do
    d="${d%/}"
  done
  printf '%s\n' "$d"
}

issues_dir=$(resolve_issues_dir) || exit 64
today="${RESUME_MEMO_TODAY:-$(date +%Y-%m-%d)}"
max_rule=200
cap_note=30
max_hits=20

# The temporary directory is made when a command first needs it. The template
# names TMPDIR: macOS "mktemp -d" without a template ignores TMPDIR, and fails
# where only TMPDIR is writable (a sandbox).
tmp=""
new_file=""
trap '[ -z "$tmp" ] || rm -rf "$tmp"; [ -z "$new_file" ] || rm -f "$new_file"' EXIT
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
       known-issue.sh search <word>...
       known-issue.sh add <slug>            (entry text on stdin: rule:, case:, prevention: lines)
       known-issue.sh recur <slug> <note>
       known-issue.sh dir
EOF
  exit 64
}

fail_write() {
  echo "known-issue.sh: could not write $1; nothing was saved" >&2
  exit 1
}

# The new entry is built next to its destination, so that the final mv is a
# rename inside one directory (atomic). A mv from TMPDIR can be a copy across
# filesystems, which leaves a half-written entry when it fails part-way.
make_new_file() {
  new_file=$(mktemp "$issues_dir/.new.XXXXXX") || {
    new_file=""
    fail_write "$issues_dir"
  }
}

# mktemp makes a file that only its owner can read. A file that replaces another
# one keeps that file's mode; a new file gets the mode that the umask gives a
# file the user wrote (the default for a note written by hand).
set_mode() { # <file> [<file whose mode to copy>]
  local mode=""
  if [ -n "${2:-}" ]; then
    mode=$(stat -c %a "$2" 2> /dev/null || stat -f %Lp "$2" 2> /dev/null)
  fi
  [ -n "$mode" ] || mode=$(printf '%o' $((0666 & ~$(umask))))
  chmod "$mode" "$1" 2> /dev/null || true
}

valid_slug() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]]
}

# An entry is a regular file whose first line starts with "rule: ". A symbolic
# link is not one: "search" does not read a link inside the directory, so a
# listed link would be an entry that the duplicate check cannot find.
is_entry() {
  [ -f "$1" ] && [ ! -L "$1" ] && [ "$(head -n 1 "$1" | LC_ALL=C cut -c1-6)" = "rule: " ]
}

# The filters below read files that may not be valid UTF-8 (notes written by
# hand, in another encoding). In a UTF-8 locale tr, sed, cut and awk stop at a
# byte that is not valid, so they run in the C locale (bytes). Only the
# character cap of "list" needs characters; see cut_chars.

# Remove leading and trailing blanks.
trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

# Scan a file for secret-like text with the memo checker. On a hit (exit 2 of
# the checker), print the pattern and line (never the value) and exit 2. Any
# other failure of the checker means the scan did not run: exit 1.
scan_or_exit() {
  local out rc
  out=$("$here/check-memo.sh" --secrets-only "$1" 2>&1)
  rc=$?
  case "$rc" in
    0) return 0 ;;
    2)
      printf '%s\n' "$out" >&2
      echo "known-issue.sh: nothing was written. Remove the value and keep only its name." >&2
      exit 2
      ;;
    *)
      printf '%s\n' "$out" >&2
      echo "known-issue.sh: the secret scan did not run (check-memo.sh exited $rc); nothing was written" >&2
      exit 1
      ;;
  esac
}

# The number on the first "count:" line (with or without a space after the
# colon, and whatever follows the number); empty when that line has no number.
# "recur" replaces this same line, so list and recur always read the same one.
read_count() {
  grep -m 1 '^count:' "$1" | LC_ALL=C sed -n 's/^count:[[:space:]]*\([0-9][0-9]*\).*/\1/p'
}

# The text on the first "last_seen:" line, without control characters.
read_last_seen() {
  grep -m 1 '^last_seen:' "$1" | LC_ALL=C sed 's/^last_seen:[[:space:]]*//; s/[[:space:]]*$//' | LC_ALL=C tr -d '\000-\037'
}

# Cut one line from stdin to N characters. Text that is not valid in the
# locale makes cut fail after a partial output, so it is cut by bytes instead.
cut_chars() { # <n>
  local text out
  text=$(cat)
  out=$(printf '%s\n' "$text" | cut -c "1-$1" 2> /dev/null) || out=$(printf '%s\n' "$text" | LC_ALL=C cut -c "1-$1")
  printf '%s\n' "$out"
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
    is_entry "$f" || continue
    slug=$(basename "$f" .md | LC_ALL=C tr -d '\000-\037')
    rule=$(grep -m 1 '^rule: ' "$f" | LC_ALL=C sed 's/^rule: //' | LC_ALL=C tr -d '\000-\010\013-\037' | cut_chars "$max_rule")
    count=$(read_count "$f")
    last=$(read_last_seen "$f")
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

# Lines of the .md files under the directory (entries and notes written by hand)
# that contain one of the words, ignoring case. Use it to see whether a cause is
# already written down before adding an entry. It needs no temporary directory,
# so an empty result always means that nothing matched.
cmd_search() {
  local term status
  [ "$#" -ge 1 ] || usage
  for term in "$@"; do
    [ -n "$term" ] || usage
  done
  [ -d "$issues_dir" ] || exit 0
  local args=()
  for term in "$@"; do
    args+=(-e "$term")
  done
  # The trailing slash makes "grep -r" enter the directory when it is a symbolic
  # link: BSD grep does not follow a link that is given without it.
  # grep and the filters run in the C locale: in a UTF-8 locale grep does not
  # match on a line that has a byte that is not valid UTF-8, and "tr" stops at
  # such a byte and drops that line and the rest, all with exit 0. The cost is
  # that -i folds the case of ASCII letters only, and that a line longer than
  # 300 bytes may be cut inside a multibyte character.
  LC_ALL=C grep -r -I -n -i -F --include='*.md' "${args[@]}" "$issues_dir/" 2> /dev/null \
    | LC_ALL=C tr -d '\000-\010\013-\037' | LC_ALL=C cut -c 1-300 \
    | LC_ALL=C awk -v max="$max_hits" 'NR <= max { print } END { if (NR > max) print "(+" NR - max " more matching lines)" }'
  status=${PIPESTATUS[0]}
  # grep exits 1 for "no match" and 2 for an error such as an unreadable directory.
  if [ "$status" -ge 2 ]; then
    echo "known-issue.sh: search could not read part of $issues_dir; the matches above may be incomplete" >&2
    exit 1
  fi
  exit 0
}

cmd_add() {
  local slug="${1:-}" rule target n f
  valid_slug "$slug" || { echo "known-issue.sh: the slug must start with a lowercase letter or digit and use only lowercase letters, digits and hyphens (at most 64 characters)" >&2; exit 64; }
  [ "$#" -eq 1 ] || usage
  make_tmp
  cat > "$tmp/entry"

  rule=$(sed -n 1p "$tmp/entry")
  case "$rule" in
    "rule: "?*) rule=$(trim "${rule#rule: }") ;;
    *) echo "known-issue.sh: the first line must be 'rule: <one line>'" >&2; exit 64 ;;
  esac
  if [ -z "$rule" ]; then
    echo "known-issue.sh: the rule is empty" >&2
    exit 64
  fi
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
  # A broken link is not "-e", and mv would replace it with the new file.
  if [ -L "$target" ]; then
    echo "known-issue.sh: $slug.md is a symbolic link. It was not changed. Choose another slug." >&2
    exit 4
  fi
  if [ -e "$target" ]; then
    if is_entry "$target"; then
      echo "known-issue.sh: $slug exists. If the cause is the same, count a repeat with: known-issue.sh recur $slug \"<note>\". If the cause is different, use another slug." >&2
    else
      echo "known-issue.sh: $slug.md exists and is not a known-issues entry (its first line is not 'rule: ...'). It was not changed. Choose another slug." >&2
    fi
    exit 4
  fi
  mkdir -p "$issues_dir" || fail_write "$issues_dir"
  make_new_file
  set_mode "$new_file"
  {
    printf 'rule: %s\ncount: 1\nfirst_seen: %s\nlast_seen: %s\n' "$rule" "$today" "$today"
    sed 1d "$tmp/entry"
  } > "$new_file" || fail_write "$new_file"
  mv "$new_file" "$target" || fail_write "$target"
  new_file=""
  echo "$target"

  n=0
  for f in "$issues_dir"/*.md; do
    is_entry "$f" && n=$((n + 1))
  done
  if [ "$n" -gt "$cap_note" ]; then
    echo "Note: $n known issues. Tell the user to delete the entries that now live in their CLAUDE.md or the skill, and the ones that no longer apply."
  fi
}

cmd_recur() {
  local slug="${1:-}" note target old old_digits new need_c=0 need_l=0
  valid_slug "$slug" || { echo "known-issue.sh: the slug must start with a lowercase letter or digit and use only lowercase letters, digits and hyphens (at most 64 characters)" >&2; exit 64; }
  [ "$#" -eq 2 ] || usage
  case "${2:-}" in
    *$'\n'*) echo "known-issue.sh: the note must be one line" >&2; exit 64 ;;
  esac
  note=$(trim "${2:-}")
  [ -n "$note" ] || usage
  if [ "${#note}" -gt "$max_rule" ]; then
    echo "known-issue.sh: the note is over $max_rule characters; keep it to one short line" >&2
    exit 64
  fi
  target="$issues_dir/$slug.md"
  # mv would replace the link itself with a plain file, and the file it points to would stay as it was.
  [ ! -L "$target" ] || { echo "known-issue.sh: $slug.md is a symbolic link. It was not changed." >&2; exit 5; }
  [ -f "$target" ] || { echo "known-issue.sh: no entry named $slug" >&2; exit 5; }
  is_entry "$target" || { echo "known-issue.sh: $slug.md is not a known-issues entry (its first line is not 'rule: ...'). It was not changed." >&2; exit 5; }
  make_tmp
  printf '%s\n' "$note" > "$tmp/note"
  scan_or_exit "$tmp/note"

  old=$(read_count "$target")
  # 10#N + 1 wraps around to a negative number in bash from 19 digits on.
  # Leading zeros do not make a number larger.
  old_digits=${old#"${old%%[!0]*}"}
  if [ "${#old_digits}" -gt 15 ]; then
    echo "known-issue.sh: the count of $slug.md has more than 15 digits. It was not changed. Fix its count: line by hand." >&2
    exit 64
  fi
  grep -q '^count:' "$target" || need_c=1
  grep -q '^last_seen:' "$target" || need_l=1
  new=$(( 10#${old:-1} + 1 ))

  # Replace the first count and last_seen line in place (the same lines that
  # read_count and read_last_seen read). A line that is missing is added after
  # line 1, which is the rule line.
  make_new_file
  set_mode "$new_file" "$target"
  LC_ALL=C awk -v c="$new" -v d="$today" -v need_c="$need_c" -v need_l="$need_l" '
    /^count:/ && !need_c && !hc { print "count: " c; hc = 1; next }
    /^last_seen:/ && !need_l && !hl { print "last_seen: " d; hl = 1; next }
    { print }
    NR == 1 { if (need_c) print "count: " c; if (need_l) print "last_seen: " d }
  ' "$target" > "$new_file" || fail_write "$new_file"
  printf 'recurrence: %s: %s\n' "$today" "$note" >> "$new_file" || fail_write "$new_file"
  mv "$new_file" "$target" || fail_write "$target"
  new_file=""
  echo "$slug: count $new"
}

command="${1:-}"
[ "$#" -gt 0 ] && shift
case "$command" in
  list) cmd_list "$@" ;;
  search) cmd_search "$@" ;;
  add) cmd_add "$@" ;;
  recur) cmd_recur "$@" ;;
  dir) printf '%s\n' "$issues_dir" ;;
  *) usage ;;
esac
