#!/usr/bin/env bash
# Tests for scripts/known-issue.sh.
set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ki="$root/scripts/known-issue.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0

report() { # label result(0 = ok) [detail]
  if [ "$2" -eq 0 ]; then
    echo "ok   $1"
    pass=$((pass + 1))
  else
    echo "FAIL $1${3:+: $3}"
    fail=$((fail + 1))
  fi
}

# run <stdin text> <args...>: sets out and rc. The memo directory is $dir.
dir="$tmp/memos"
issues="$dir/known-issues"
run() {
  local input="$1"
  shift
  out=$(printf '%s' "$input" | RESUME_MEMO_DIR="$dir" RESUME_MEMO_TODAY="${TODAY:-2026-11-24}" bash "$ki" "$@" 2>&1)
  rc=$?
}
expect_rc() { # label want
  if [ "$rc" -eq "$2" ]; then report "$1" 0; else report "$1" 1 "exit $rc, want $2: $out"; fi
}
has() { # label needle
  if printf '%s' "$out" | grep -q -F -e "$2"; then report "$1" 0; else report "$1" 1 "output lacks '$2': $out"; fi
}
lacks() { # label needle
  if printf '%s' "$out" | grep -q -F -e "$2"; then report "$1" 1 "output has '$2'"; else report "$1" 0; fi
}
file_has() { # label file needle
  if grep -q -F -e "$3" "$2" 2>/dev/null; then report "$1" 0; else report "$1" 1 "$2 lacks '$3'"; fi
}

entry='rule: Write a plain value that contains ": " as a | block scalar
case: the check reported next[0] is Hash, not a string
prevention: write the item as - | from the start'

# Secret-like strings are assembled here so that no real-looking token sits in the repository.
gh_token="ghp_$(printf 'a%.0s' $(seq 1 36))"

# --- list on an empty or missing directory
run "" list
expect_rc "list: missing directory exits 0" 0
if [ -z "$out" ]; then report "list: missing directory prints nothing" 0; else report "list: missing directory prints nothing" 1 "$out"; fi

# --- add
run "$entry" add yaml-colon-in-plain-item
expect_rc "add: creates an entry" 0
has "add: prints the path" "$issues/yaml-colon-in-plain-item.md"
f="$issues/yaml-colon-in-plain-item.md"
file_has "add: header has rule on the first line" "$f" 'rule: Write a plain value that contains ": " as a | block scalar'
file_has "add: header has count 1" "$f" 'count: 1'
file_has "add: header has first_seen" "$f" 'first_seen: 2026-11-24'
file_has "add: header has last_seen" "$f" 'last_seen: 2026-11-24'
file_has "add: keeps the case line" "$f" 'case: the check reported next[0] is Hash, not a string'
file_has "add: keeps the prevention line" "$f" 'prevention: write the item as - | from the start'
if [ "$(head -n 1 "$f")" = 'rule: Write a plain value that contains ": " as a | block scalar' ]; then
  report "add: the rule is line 1" 0
else
  report "add: the rule is line 1" 1 "$(head -n 1 "$f")"
fi

before=$(cat "$f")
run "$entry" add yaml-colon-in-plain-item
expect_rc "add: an existing slug exits 4" 4
has "add: an existing slug points at recur" "recur"
if [ "$before" = "$(cat "$f")" ]; then report "add: an existing entry is left unchanged" 0; else report "add: an existing entry is left unchanged" 1; fi

for bad in '../evil' 'Upper' 'a/b' '' '-lead' 'has space'; do
  run "$entry" add "$bad"
  expect_rc "add: bad slug '$bad' exits 64" 64
done
if [ ! -e "$dir/evil.md" ] && [ ! -e "$tmp/evil.md" ]; then report "add: a bad slug writes nothing outside the directory" 0; else report "add: a bad slug writes nothing outside the directory" 1; fi

run 'rule: only a rule
case: only a case' add no-prevention
expect_rc "add: a missing prevention line exits 64" 64
if [ ! -e "$issues/no-prevention.md" ]; then report "add: a refused entry leaves no file" 0; else report "add: a refused entry leaves no file" 1; fi

run 'case: no rule first
rule: second line
prevention: x' add rule-not-first
expect_rc "add: the rule must be the first line" 64

long_rule=$(printf 'x%.0s' $(seq 1 201))
run "rule: $long_rule
case: c
prevention: p" add long-rule
expect_rc "add: a rule over 200 characters exits 64" 64

run "$entry
note: token $gh_token" add with-secret
expect_rc "add: secret-like text exits 2" 2
has "add: names the pattern" "GitHub token"
lacks "add: does not echo the value" "$gh_token"
if [ ! -e "$issues/with-secret.md" ]; then report "add: a secret leaves no file" 0; else report "add: a secret leaves no file" 1; fi

# --- recur
TODAY=2026-11-25 run "" recur yaml-colon-in-plain-item "hit again while updating next"
expect_rc "recur: bumps an entry" 0
file_has "recur: count is 2" "$f" 'count: 2'
file_has "recur: last_seen moves" "$f" 'last_seen: 2026-11-25'
file_has "recur: first_seen stays" "$f" 'first_seen: 2026-11-24'
file_has "recur: appends a recurrence line" "$f" 'recurrence: 2026-11-25: hit again while updating next'
if [ "$(head -n 1 "$f")" = 'rule: Write a plain value that contains ": " as a | block scalar' ]; then
  report "recur: the rule stays on line 1" 0
else
  report "recur: the rule stays on line 1" 1
fi

TODAY=2026-11-26 run "" recur yaml-colon-in-plain-item "third time"
file_has "recur: count is 3 after a second recurrence" "$f" 'count: 3'
n_rec=$(grep -c '^recurrence: ' "$f")
if [ "$n_rec" -eq 2 ]; then report "recur: one recurrence line per call" 0; else report "recur: one recurrence line per call" 1 "$n_rec"; fi

run "" recur no-such-entry "x"
expect_rc "recur: an unknown slug exits 5" 5

run "" recur yaml-colon-in-plain-item "token $gh_token"
expect_rc "recur: a secret in the note exits 2" 2
file_has "recur: a refused note leaves the count" "$f" 'count: 3'

run "" recur yaml-colon-in-plain-item
expect_rc "recur: a missing note exits 64" 64

printf 'multi\nline' > "$tmp/note"
run "" recur yaml-colon-in-plain-item "$(cat "$tmp/note")"
expect_rc "recur: a note with a newline exits 64" 64

# --- list order, cap and cleaning
run "rule: second rule
case: c
prevention: p" add b-once
run "rule: third rule
case: c
prevention: p" add c-once
TODAY=2026-11-27 run "" recur c-once "again"
run "" list
expect_rc "list: exits 0" 0
first=$(printf '%s\n' "$out" | sed -n 1p)
second=$(printf '%s\n' "$out" | sed -n 2p)
third=$(printf '%s\n' "$out" | sed -n 3p)
case "$first" in "yaml-colon-in-plain-item x3 2026-11-26: "*) report "list: the highest count comes first" 0 ;; *) report "list: the highest count comes first" 1 "$first" ;; esac
case "$second" in "c-once x2 2026-11-27: third rule") report "list: next by count" 0 ;; *) report "list: next by count" 1 "$second" ;; esac
case "$third" in "b-once x1 2026-11-24: second rule") report "list: a count of 1 is listed last" 0 ;; *) report "list: a count of 1 is listed last" 1 "$third" ;; esac

run "" list --max 2
n_lines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
if [ "$n_lines" -eq 3 ]; then report "list: --max 2 prints two entries and a remainder line" 0; else report "list: --max 2 prints two entries and a remainder line" 1 "$n_lines lines: $out"; fi
has "list: the remainder line counts the rest" "(+1 more"
lacks "list: the capped entry is left out" "b-once"

run "" list --max 0
expect_rc "list: --max 0 exits 64" 64
run "" list --max abc
expect_rc "list: a non-numeric --max exits 64" 64

printf 'rule: has a control \033[31mred\033 character\ncount: 1\nfirst_seen: 2026-11-20\nlast_seen: 2026-11-20\ncase: c\nprevention: p\n' > "$issues/ctrl.md"
run "" list
if printf '%s' "$out" | grep -q "$(printf '\033')"; then report "list: strips control characters" 1; else report "list: strips control characters" 0; fi
has "list: still lists the entry with a control character" "ctrl x1"

long=$(printf 'y%.0s' $(seq 1 300))
printf 'rule: %s\ncount: 1\nfirst_seen: 2026-11-19\nlast_seen: 2026-11-19\ncase: c\nprevention: p\n' "$long" > "$issues/long.md"
run "" list
long_line=$(printf '%s\n' "$out" | grep '^long ')
if [ "${#long_line}" -le 230 ]; then report "list: a long rule is cut" 0; else report "list: a long rule is cut" 1 "${#long_line} characters"; fi

# A file without the header lines is still listed, with count 1, not skipped silently.
printf 'rule: hand-written\ncase: c\nprevention: p\n' > "$issues/handmade.md"
run "" list
has "list: a hand-written entry without count is listed as x1" "handmade x1"

# Files that are not entries are ignored.
printf 'not an entry\n' > "$issues/README.txt"
run "" list
lacks "list: ignores a file that is not .md" "README"

# --- directory selection
mkdir -p "$tmp/home/.claude/resume-memos/known-issues"
printf 'rule: from home\ncount: 1\nfirst_seen: 2026-11-18\nlast_seen: 2026-11-18\ncase: c\nprevention: p\n' > "$tmp/home/.claude/resume-memos/known-issues/from-home.md"
out=$(HOME="$tmp/home" bash "$ki" list 2>&1 </dev/null)
rc=$?
expect_rc "list: the default directory is under HOME" 0
has "list: the default directory is read" "from-home"

# --- temporary directory
# macOS "mktemp -d" without a template ignores TMPDIR and fails where only TMPDIR is writable (a sandbox),
# so the script must ask for a template under TMPDIR, and say so when that fails.
mkdir -p "$tmp/mytmp"
TMPDIR="$tmp/mytmp" run "$entry" add tmpdir-entry
expect_rc "tmpdir: add works with TMPDIR set to another directory" 0
if [ -z "$(ls -A "$tmp/mytmp")" ]; then report "tmpdir: the temporary directory is removed afterwards" 0; else report "tmpdir: the temporary directory is removed afterwards" 1 "$(ls -A "$tmp/mytmp")"; fi

TMPDIR="$tmp/no-such-tmp" run "$entry" add tmpdir-missing
expect_rc "tmpdir: add exits 1 when TMPDIR does not exist" 1
has "tmpdir: the message names the temporary directory" "temporary directory"
if [ ! -e "$issues/tmpdir-missing.md" ]; then report "tmpdir: a failed add leaves no file" 0; else report "tmpdir: a failed add leaves no file" 1; fi

TMPDIR="$tmp/no-such-tmp" run "" recur tmpdir-entry "again"
expect_rc "tmpdir: recur exits 1 when TMPDIR does not exist" 1
file_has "tmpdir: a failed recur leaves the count" "$issues/tmpdir-entry.md" 'count: 1'

TMPDIR="$tmp/no-such-tmp" run "" list
expect_rc "tmpdir: list exits 1 when there are entries and TMPDIR does not exist" 1

mv "$issues" "$tmp/issues-moved"
TMPDIR="$tmp/no-such-tmp" run "" list
expect_rc "tmpdir: list needs no temporary directory when there are no entries" 0
mv "$tmp/issues-moved" "$issues"

mkdir -p "$tmp/empty-memos/known-issues"
out=$(RESUME_MEMO_DIR="$tmp/empty-memos" TMPDIR="$tmp/no-such-tmp" bash "$ki" list 2>&1 </dev/null)
rc=$?
expect_rc "tmpdir: list needs no temporary directory for an empty known-issues directory" 0

# --- usage
run "" nonsense
expect_rc "usage: an unknown command exits 64" 64
run ""
expect_rc "usage: no command exits 64" 64

echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
