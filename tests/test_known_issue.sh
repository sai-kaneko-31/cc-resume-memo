#!/usr/bin/env bash
# Tests for scripts/known-issue.sh.
set -u

# The settings of the machine may export RESUME_MEMO_ISSUES_DIR. The tests must not write there.
unset RESUME_MEMO_ISSUES_DIR

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

# --- hand-written entries and blank input
write_entry() { # <slug> <content>
  mkdir -p "$issues"
  printf '%s' "$2" > "$issues/$1.md"
}
write_entry oct9 $'rule: a\ncount: 09\nlast_seen: 2026-11-01\ncase: c\nprevention: p\n'
run "" recur oct9 "n"
file_has "recur: a count with a leading zero is read as decimal (09 becomes 10)" "$issues/oct9.md" 'count: 10'
write_entry oct10 $'rule: a\ncount: 010\nlast_seen: 2026-11-01\ncase: c\nprevention: p\n'
run "" recur oct10 "n"
file_has "recur: 010 becomes 11, not 9" "$issues/oct10.md" 'count: 11'

# A file whose first line is not "rule: " is not an entry, even when it has a count line.
write_entry count-first $'count: 3\nrule: a\ncase: c\nprevention: p\n'
before_count_first=$(cksum "$issues/count-first.md")
run "" recur count-first "n"
expect_rc "recur: a file whose first line is a count line is not an entry (exit 5)" 5
if [ "$(cksum "$issues/count-first.md")" = "$before_count_first" ]; then report "recur: that file is left byte-identical" 0; else report "recur: that file is left byte-identical" 1; fi
run "" list
lacks "list: a file whose first line is a count line is not listed" "count-first"

write_entry count-words $'rule: a\ncount: 3 times\nlast_seen: 2026-11-01\ncase: c\nprevention: p\n'
run "" recur count-words "n"
n_count=$(grep -c '^count: ' "$issues/count-words.md")
if [ "$n_count" -eq 1 ]; then report "recur: a count line with words after the number stays one line" 0; else report "recur: a count line with words after the number stays one line" 1 "$n_count lines"; fi
file_has "recur: the number after the words is counted from 3" "$issues/count-words.md" 'count: 4'

: > "$issues/empty-entry.md"
run "" recur empty-entry "n"
expect_rc "recur: an empty file is not an entry (exit 5)" 5
if [ ! -s "$issues/empty-entry.md" ]; then report "recur: an empty file stays empty" 0; else report "recur: an empty file stays empty" 1; fi

write_entry no-newline $'rule: a\ncount: 1\nlast_seen: 2026-11-01\ncase: c\nprevention: p'
run "" recur no-newline "n"
file_has "recur: a file without a final newline keeps its last line" "$issues/no-newline.md" 'prevention: p'
if grep -q '^recurrence: ' "$issues/no-newline.md"; then report "recur: the recurrence line starts on its own line" 0; else report "recur: the recurrence line starts on its own line" 1; fi

run $'rule:   \ncase: c\nprevention: p' add blank-rule
expect_rc "add: a blank rule exits 64" 64
run "" recur oct9 "   "
expect_rc "recur: a blank note exits 64" 64
run $'rule:   spaced out   \ncase: c\nprevention: p' add trimmed-rule
if [ "$(head -n 1 "$issues/trimmed-rule.md")" = 'rule: spaced out' ]; then report "add: the rule is stored without surrounding blanks" 0; else report "add: the rule is stored without surrounding blanks" 1 "$(head -n 1 "$issues/trimmed-rule.md")"; fi

# --- the final mv is a rename inside the entry directory
# A fake mv logs its source, so the test can see where the new file was built: a source in another
# directory (TMPDIR) would make mv copy across filesystems and leave a half-written entry on failure.
mkdir -p "$tmp/fakebin"
printf '#!/bin/bash\nprintf "%%s\\n" "$1" >> "$MV_LOG"\nexec /bin/mv "$@"\n' > "$tmp/fakebin/mv"
chmod +x "$tmp/fakebin/mv"
: > "$tmp/mv.log"
out=$(printf '%s' "$entry" | PATH="$tmp/fakebin:$PATH" MV_LOG="$tmp/mv.log" RESUME_MEMO_DIR="$dir" bash "$ki" add same-dir-add 2>&1)
rc=$?
expect_rc "mv: add works with a logging mv in front" 0
out=$(PATH="$tmp/fakebin:$PATH" MV_LOG="$tmp/mv.log" RESUME_MEMO_DIR="$dir" bash "$ki" recur same-dir-add "n" 2>&1 </dev/null)
rc=$?
expect_rc "mv: recur works with a logging mv in front" 0
n_mv=$(wc -l < "$tmp/mv.log" | tr -d ' ')
n_same=$(grep -c "^$issues/" "$tmp/mv.log")
if [ "$n_mv" -eq 2 ] && [ "$n_same" -eq 2 ]; then report "mv: add and recur move a file built inside the entry directory" 0; else report "mv: add and recur move a file built inside the entry directory" 1 "$n_same of $n_mv sources are under $issues: $(cat "$tmp/mv.log")"; fi
leftover=""
for f in "$issues"/.new.*; do
  [ -e "$f" ] && leftover="$leftover $f"
done
if [ -n "$leftover" ]; then report "mv: no temporary entry file is left behind" 1 "$leftover"; else report "mv: no temporary entry file is left behind" 0; fi

# --- count and last_seen lines are read the same way by list and recur
write_entry nospace $'rule: a\ncount:5\nlast_seen:2026-11-01\ncase: c\nprevention: p\n'
run "" recur nospace "n"
n_count=$(grep -c '^count:' "$issues/nospace.md")
if [ "$n_count" -eq 1 ]; then report "recur: count:5 without a space stays one count line" 0; else report "recur: count:5 without a space stays one count line" 1 "$n_count lines"; fi
file_has "recur: count:5 becomes 6" "$issues/nospace.md" 'count: 6'
n_last=$(grep -c '^last_seen:' "$issues/nospace.md")
if [ "$n_last" -eq 1 ]; then report "recur: last_seen without a space stays one line" 0; else report "recur: last_seen without a space stays one line" 1 "$n_last lines"; fi

write_entry dup-count $'rule: a\ncount: many\ncount: 4\nlast_seen: 2026-11-01\ncase: c\nprevention: p\n'
run "" recur dup-count "n"
run "" list
has "list: with two count lines, list and recur agree on the first one" "dup-count x2 "

# --- a failed write is reported, not hidden
if [ "$(id -u)" -ne 0 ]; then
  write_entry readonly-entry $'rule: a\ncount: 1\nlast_seen: 2026-11-01\ncase: c\nprevention: p\n'
  chmod 555 "$issues"
  run "$entry" add cannot-write
  expect_rc "write failure: add exits 1 when the directory is read-only" 1
  # The success line is the path alone; the error message names the path inside a sentence.
  if printf '%s\n' "$out" | grep -q -x -F "$issues/cannot-write.md"; then report "write failure: add prints no success line" 1; else report "write failure: add prints no success line" 0; fi
  has "write failure: add says nothing was saved" "nothing was saved"
  run "" recur readonly-entry "n"
  expect_rc "write failure: recur exits 1 when the directory is read-only" 1
  lacks "write failure: recur prints no count" "count 2"
  chmod 755 "$issues"
  file_has "write failure: the entry keeps its count" "$issues/readonly-entry.md" 'count: 1'
else
  echo "SKIP write failure cases: running as root, a read-only directory can still be written"
fi

# --- a secret scan that did not run is not reported as a secret
mkdir -p "$tmp/scripts-copy"
cp "$root"/scripts/*.sh "$tmp/scripts-copy/"
printf '#!/usr/bin/env bash\nexit 64\n' > "$tmp/scripts-copy/check-memo.sh"
out=$(printf '%s' "$entry" | RESUME_MEMO_DIR="$dir" bash "$tmp/scripts-copy/known-issue.sh" add scan-broken 2>&1)
rc=$?
expect_rc "scan failure: a scan that did not run exits 1, not 2" 1
has "scan failure: the message says the scan did not run" "did not run"
lacks "scan failure: it does not tell the user to remove a value" "Remove the value"
if [ ! -e "$issues/scan-broken.md" ]; then report "scan failure: nothing is written" 0; else report "scan failure: nothing is written" 1; fi

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

# --- a directory that also holds files the user wrote by hand (area files)
# RESUME_MEMO_ISSUES_DIR points the log at a directory the user already fills: its files have no
# "rule:" first line, and the script must neither list them, count them, nor change them.
shared="$tmp/shared"
mkdir -p "$shared"
printf '# Known issues: sample（`~/git/sample`）の作業\n\nこのファイルは常時は読み込まれない。\n\n## 見出しの 1 件目\n\n事例: sample / 何か (2026-11-01)。内容。\n\n防止策: 確かめる。\n' > "$shared/sample.md"
printf 'old archive text\n' > "$shared/_orig-20260101.md"
before_sum=$(cksum "$shared/sample.md")
run_shared() { # <stdin text> <args...>
  local input="$1"
  shift
  out=$(printf '%s' "$input" | RESUME_MEMO_ISSUES_DIR="$shared" RESUME_MEMO_DIR="$tmp/unused-memos" RESUME_MEMO_TODAY=2026-11-24 bash "$ki" "$@" 2>&1)
  rc=$?
}

run_shared "$entry" add shared-first
expect_rc "shared dir: add writes into RESUME_MEMO_ISSUES_DIR" 0
if [ -f "$shared/shared-first.md" ] && [ ! -e "$tmp/unused-memos" ]; then report "shared dir: the memo directory is not used" 0; else report "shared dir: the memo directory is not used" 1; fi
run_shared "" list
has "shared dir: list shows the entry" "shared-first x1"
lacks "shared dir: list does not show the area file" "sample"
lacks "shared dir: list does not show the archive file" "_orig"
lacks "shared dir: list does not show a heading of an area file" "見出し"

run_shared "" recur sample "n"
expect_rc "shared dir: recur on an area file exits 5" 5
has "shared dir: recur says it is not an entry" "not a known-issues entry"
if [ "$(cksum "$shared/sample.md")" = "$before_sum" ]; then report "shared dir: a refused recur leaves the area file byte-identical" 0; else report "shared dir: a refused recur leaves the area file byte-identical" 1; fi

run_shared "$entry" add sample
expect_rc "shared dir: add with the name of an area file exits 4" 4
has "shared dir: add says the file is not an entry" "not a known-issues entry"
lacks "shared dir: add does not suggest recur for an area file" "known-issue.sh recur"
if [ "$(cksum "$shared/sample.md")" = "$before_sum" ]; then report "shared dir: a refused add leaves the area file byte-identical" 0; else report "shared dir: a refused add leaves the area file byte-identical" 1; fi

# --- the "too many entries" note counts entries only
many="$tmp/many"
mkdir -p "$many"
for i in $(seq 1 40); do printf '# area %s\n\n## x\n' "$i" > "$many/area-$i.md"; done
for i in $(seq 1 31); do
  out=$(printf '%s' "$entry" | RESUME_MEMO_ISSUES_DIR="$many" bash "$ki" add "entry-$i" 2>&1)
  if [ "$i" -eq 30 ]; then
    if printf '%s' "$out" | grep -q '^Note:'; then report "note: 30 entries and 40 area files give no note" 1; else report "note: 30 entries and 40 area files give no note" 0; fi
  fi
  if [ "$i" -eq 31 ]; then
    if printf '%s' "$out" | grep -q '^Note: 31 known issues'; then report "note: the 31st entry gives a note that counts 31" 0; else report "note: the 31st entry gives a note that counts 31" 1 "$out"; fi
  fi
done

# --- search: find a cause in every file of the directory before adding an entry
run_shared "" search "何か"
has "search: finds a line of an area file" "sample.md"
run_shared "" search "plain value"
has "search: finds a line of an entry" "shared-first.md"
run_shared "" search "NO-SUCH-WORD"
expect_rc "search: no match exits 0" 0
if [ -z "$out" ]; then report "search: no match prints nothing" 0; else report "search: no match prints nothing" 1 "$out"; fi
run_shared "" search "PLAIN VALUE"
has "search: ignores case" "shared-first.md"
run_shared "" search "-h"
expect_rc "search: a term that starts with a dash is a term" 0
run_shared "" search
expect_rc "search: no term exits 64" 64
printf 'secret leftover plain value\n' > "$shared/.new.ABC123"
run_shared "" search "leftover"
if [ -z "$out" ]; then report "search: ignores a leftover .new file" 0; else report "search: ignores a leftover .new file" 1 "$out"; fi
printf '%s\n' "line plain value" > "$shared/many-hits.md"
for i in $(seq 1 30); do printf 'plain value %s\n' "$i" >> "$shared/many-hits.md"; done
run_shared "" search "plain value"
has "search: more than 20 matches end with a remainder line" "more matching lines"
mkdir -p "$tmp/nodir"
out=$(RESUME_MEMO_ISSUES_DIR="$tmp/nodir/missing" bash "$ki" search "x" 2>&1 </dev/null)
rc=$?
expect_rc "search: a missing directory exits 0" 0

# --- dir: where the entries go, with a leading ~/ expanded
run_shared "" dir
if [ "$out" = "$shared" ]; then report "dir: prints RESUME_MEMO_ISSUES_DIR" 0; else report "dir: prints RESUME_MEMO_ISSUES_DIR" 1 "$out"; fi
# shellcheck disable=SC2088  # a literal "~/" is the input under test
out=$(cd "$tmp" && RESUME_MEMO_ISSUES_DIR='~/ki-home' HOME="$tmp/home" bash "$ki" dir 2>&1 </dev/null)
if [ "$out" = "$tmp/home/ki-home" ]; then report "dir: a leading ~/ is expanded with HOME" 0; else report "dir: a leading ~/ is expanded with HOME" 1 "$out"; fi
out=$(RESUME_MEMO_ISSUES_DIR='' RESUME_MEMO_DIR="$tmp/memo-x" bash "$ki" dir 2>&1 </dev/null)
if [ "$out" = "$tmp/memo-x/known-issues" ]; then report "dir: an empty RESUME_MEMO_ISSUES_DIR falls back to the memo directory" 0; else report "dir: an empty RESUME_MEMO_ISSUES_DIR falls back to the memo directory" 1 "$out"; fi
out=$(RESUME_MEMO_DIR="$tmp/memo-y" bash "$ki" dir 2>&1 </dev/null)
if [ "$out" = "$tmp/memo-y/known-issues" ]; then report "dir: the default is known-issues inside the memo directory" 0; else report "dir: the default is known-issues inside the memo directory" 1 "$out"; fi
# shellcheck disable=SC2088  # a literal "~/" is the input under test
out=$(cd "$tmp" && RESUME_MEMO_ISSUES_DIR='~/ki-home' HOME="$tmp/home" bash -c 'printf "%s" "$1" | bash "$2" add tilde-entry' _ "$entry" "$ki" 2>&1)
if [ -f "$tmp/home/ki-home/tilde-entry.md" ]; then report "dir: add writes under the expanded ~/ directory" 0; else report "dir: add writes under the expanded ~/ directory" 1 "$out"; fi

# --- search needs no temporary directory, so an empty result means that nothing matched
TMPDIR="$tmp/no-such-tmp" run_shared "" search "block scalar"
expect_rc "search: works when TMPDIR does not exist" 0
has "search: still prints the matches when TMPDIR does not exist" "shared-first.md"

# --- search lists one more line than the cap only as a remainder, and keeps paths clean
run_shared "" search "plain value"
if [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 21 ]; then report "search: prints 20 lines and one remainder line" 0; else report "search: prints 20 lines and one remainder line" 1 "$(printf '%s\n' "$out" | wc -l)"; fi
out=$(RESUME_MEMO_ISSUES_DIR="$shared/" bash "$ki" search "plain value" 2>&1 </dev/null)
if printf '%s' "$out" | grep -q '//'; then report "search: a trailing slash in the setting does not double up in the paths" 1 "$out"; else report "search: a trailing slash in the setting does not double up in the paths" 0; fi
out=$(RESUME_MEMO_ISSUES_DIR="$shared//" bash "$ki" dir 2>&1 </dev/null)
if [ "$out" = "$shared" ]; then report "dir: trailing slashes are dropped" 0; else report "dir: trailing slashes are dropped" 1 "$out"; fi

# --- a directory that is a symbolic link (BSD "grep -r" does not enter one that is given as it is)
real="$tmp/real-issues"
mkdir -p "$real"
printf '%s' "$entry" | RESUME_MEMO_ISSUES_DIR="$real" bash "$ki" add linked-entry > /dev/null 2>&1
ln -s "$real" "$tmp/link-issues"
run_link() { # <stdin text> <args...>
  local input="$1"
  shift
  out=$(printf '%s' "$input" | RESUME_MEMO_ISSUES_DIR="$tmp/link-issues" RESUME_MEMO_TODAY=2026-11-24 bash "$ki" "$@" 2>&1)
  rc=$?
}
run_link "" search "plain value"
has "symlinked dir: search finds the entry" "linked-entry.md"
run_link "" list
has "symlinked dir: list shows the entry" "linked-entry x1"
run_link "$entry" add linked-second
if [ -f "$real/linked-second.md" ]; then report "symlinked dir: add writes into the directory it points to" 0; else report "symlinked dir: add writes into the directory it points to" 1 "$out"; fi
run_link "" recur linked-entry "again"
expect_rc "symlinked dir: recur counts a repeat" 0

# --- a symbolic link in place of an entry file is never written through or replaced
syml="$tmp/syml"
mkdir -p "$syml"
ln -s "$tmp/nowhere.md" "$syml/dangling.md"
out=$(printf '%s' "$entry" | RESUME_MEMO_ISSUES_DIR="$syml" bash "$ki" add dangling 2>&1)
rc=$?
expect_rc "symlink: add over a broken link exits 4" 4
has "symlink: add says it is a symbolic link" "symbolic link"
if [ -L "$syml/dangling.md" ] && [ ! -e "$tmp/nowhere.md" ]; then report "symlink: a refused add leaves the broken link as it was" 0; else report "symlink: a refused add leaves the broken link as it was" 1; fi
printf 'rule: kept\ncase: c\nprevention: p\ncount: 1\nfirst_seen: 2026-01-01\nlast_seen: 2026-01-01\n' > "$tmp/elsewhere.md"
ln -s "$tmp/elsewhere.md" "$syml/pointing.md"
link_sum=$(cksum "$tmp/elsewhere.md")
out=$(RESUME_MEMO_ISSUES_DIR="$syml" bash "$ki" recur pointing "again" 2>&1 </dev/null)
rc=$?
expect_rc "symlink: recur on a link to an entry exits 5" 5
if [ -L "$syml/pointing.md" ] && [ "$(cksum "$tmp/elsewhere.md")" = "$link_sum" ]; then report "symlink: a refused recur leaves the link and its target as they were" 0; else report "symlink: a refused recur leaves the link and its target as they were" 1; fi
out=$(RESUME_MEMO_ISSUES_DIR="$syml" bash "$ki" recur dangling "again" 2>&1 </dev/null)
rc=$?
expect_rc "symlink: recur on a broken link exits 5" 5

# --- other shapes of file in the directory
odd="$tmp/odd"
mkdir -p "$odd/folder.md"
printf 'rule: inside a folder named like a note\ncase: c\nprevention: p\n' > "$odd/folder.md/inner.md"
printf 'rule: crlf rule\r\ncase: c\r\nprevention: p\r\ncount: 2\r\nfirst_seen: 2026-01-01\r\nlast_seen: 2026-01-02\r\n' > "$odd/crlf-entry.md"
printf '\357\273\277rule: bom rule\ncase: c\nprevention: p\n' > "$odd/bom.md"
printf 'plain value\0binary\n' > "$odd/binary.md"
run_odd() { # <stdin text> <args...>
  local input="$1"
  shift
  out=$(printf '%s' "$input" | RESUME_MEMO_ISSUES_DIR="$odd" RESUME_MEMO_TODAY=2026-11-24 bash "$ki" "$@" 2>&1)
  rc=$?
}
run_odd "" list
expect_rc "odd files: list exits 0 with a folder named *.md in the directory" 0
has "odd files: list shows the entry with CRLF line ends, with its count and date" "crlf-entry x2 2026-01-02: crlf rule"
if printf '%s' "$out" | grep -q "$(printf '\r')"; then report "odd files: list prints no carriage return" 1; else report "odd files: list prints no carriage return" 0; fi
lacks "odd files: list skips a folder named *.md" "folder"
lacks "odd files: list skips a file that starts with a byte order mark" "bom"
run_odd "" recur crlf-entry "again"
expect_rc "odd files: recur counts an entry with CRLF line ends" 0
has "odd files: the count goes from 2 to 3" "count 3"
run_odd "$entry" add folder
expect_rc "odd files: add over a folder named like a note exits 4" 4
run_odd "$entry" add bom
expect_rc "odd files: add over a file that starts with a byte order mark exits 4 (it is not an entry)" 4
has "odd files: the message says it is not an entry" "not a known-issues entry"
run_odd "" recur bom "again"
expect_rc "odd files: recur on a file that starts with a byte order mark exits 5" 5
run_odd "" search "plain value"
lacks "odd files: search skips a binary file" "binary.md"
run_odd "" search "inside a folder"
has "odd files: search reads a note in a subdirectory" "inner.md"

# --- ~name is not expanded, and must not create a directory named "~name"
cwd="$tmp/cwd-tilde"
mkdir -p "$cwd"
for cmd in list dir search; do
  # shellcheck disable=SC2088  # a literal "~bob" is the input under test
  out=$(cd "$cwd" && RESUME_MEMO_ISSUES_DIR='~bob/x' bash "$ki" "$cmd" word 2>&1 </dev/null)
  rc=$?
  expect_rc "tilde user: $cmd exits 64" 64
done
has "tilde user: the message says what to write instead" "full path"
# shellcheck disable=SC2088  # a literal "~bob" is the input under test
out=$(cd "$cwd" && printf '%s' "$entry" | RESUME_MEMO_ISSUES_DIR='~bob/x' bash "$ki" add tilde-user 2>&1)
rc=$?
expect_rc "tilde user: add exits 64" 64
if [ -z "$(ls -A "$cwd")" ]; then report "tilde user: no directory is created in the working directory" 0; else report "tilde user: no directory is created in the working directory" 1 "$(ls -A "$cwd")"; fi

# --- the file mode follows the umask, and a repeat keeps the mode of the entry
mode_of() { stat -c %a "$1" 2> /dev/null || stat -f %Lp "$1"; }
modes="$tmp/modes"
mkdir -p "$modes"
(umask 022; printf '%s' "$entry" | RESUME_MEMO_ISSUES_DIR="$modes" bash "$ki" add mode-022 > /dev/null 2>&1)
(umask 077; printf '%s' "$entry" | RESUME_MEMO_ISSUES_DIR="$modes" bash "$ki" add mode-077 > /dev/null 2>&1)
if [ "$(mode_of "$modes/mode-022.md")" = "644" ]; then report "mode: umask 022 gives 644" 0; else report "mode: umask 022 gives 644" 1 "$(mode_of "$modes/mode-022.md")"; fi
if [ "$(mode_of "$modes/mode-077.md")" = "600" ]; then report "mode: umask 077 gives 600" 0; else report "mode: umask 077 gives 600" 1 "$(mode_of "$modes/mode-077.md")"; fi
chmod 640 "$modes/mode-022.md"
(umask 077; RESUME_MEMO_ISSUES_DIR="$modes" bash "$ki" recur mode-022 "again" > /dev/null 2>&1 </dev/null)
if [ "$(mode_of "$modes/mode-022.md")" = "640" ]; then report "mode: a repeat keeps the mode of the entry" 0; else report "mode: a repeat keeps the mode of the entry" 1 "$(mode_of "$modes/mode-022.md")"; fi

# --- search keeps the lines after a line that is not valid UTF-8
# In a UTF-8 locale "tr" stops at such a byte and drops that line and the rest, with exit 0.
utf8=$(locale -a 2> /dev/null | grep -i -m 1 'utf-\{0,1\}8')
bad="$tmp/bad-bytes"
mkdir -p "$bad"
printf 'foo \377\376 bar\nfoo second\n' > "$bad/n.md"
if [ -n "$utf8" ]; then
  out=$(LC_ALL="$utf8" RESUME_MEMO_ISSUES_DIR="$bad" bash "$ki" search foo 2>&1 </dev/null)
  rc=$?
  expect_rc "search: a line that is not valid UTF-8 exits 0 in a UTF-8 locale" 0
  has "search: the line after a line that is not valid UTF-8 is still printed" "foo second"
else
  report "search: no UTF-8 locale on this machine, test skipped" 0
fi

# --- search says so when it could not read part of the directory (an empty output is then not "no match")
unread="$tmp/unreadable"
mkdir -p "$unread/sub"
printf 'foo in a note\n' > "$unread/sub/n.md"
printf 'foo in the top note\n' > "$unread/top.md"
if [ "$(id -u)" -ne 0 ]; then
  chmod 000 "$unread/sub"
  out=$(RESUME_MEMO_ISSUES_DIR="$unread" bash "$ki" search foo 2>&1 </dev/null)
  rc=$?
  chmod 755 "$unread/sub"
  expect_rc "search: an unreadable subdirectory exits 1" 1
  has "search: the message says the result may be incomplete" "incomplete"
  has "search: the matches that could be read are still printed" "top.md"
else
  report "search: running as root, the unreadable-directory test is skipped" 0
fi

# --- a symbolic link is not an entry: list does not show it, because search cannot find it
lnk="$tmp/lnk-entries"
mkdir -p "$lnk"
printf 'rule: real rule\ncase: c\nprevention: p\n' > "$lnk/real.md"
ln -s real.md "$lnk/alias.md"
out=$(RESUME_MEMO_ISSUES_DIR="$lnk" bash "$ki" list 2>&1 </dev/null)
has "symlink: list shows the file the link points to" "real x1"
lacks "symlink: list does not show the link" "alias"

# --- HOME: ~ needs it, and a trailing slash of HOME does not double up
# shellcheck disable=SC2088  # a literal "~" is the input under test
out=$(HOME='' RESUME_MEMO_ISSUES_DIR='~/x' bash "$ki" dir 2>&1 </dev/null)
rc=$?
expect_rc "home: ~/x with an empty HOME exits 64" 64
has "home: the message names HOME" "HOME"
# shellcheck disable=SC2088  # a literal "~" is the input under test
out=$(env -u HOME RESUME_MEMO_ISSUES_DIR='~/x' bash "$ki" dir 2>&1 </dev/null)
rc=$?
expect_rc "home: ~/x with HOME unset exits 64" 64
# shellcheck disable=SC2088  # a literal "~" is the input under test
out=$(HOME=/tmp/h/ RESUME_MEMO_ISSUES_DIR='~/x' bash "$ki" dir 2>&1 </dev/null)
if [ "$out" = "/tmp/h/x" ]; then report "home: a trailing slash of HOME does not double up" 0; else report "home: a trailing slash of HOME does not double up" 1 "$out"; fi
# shellcheck disable=SC2088  # a literal "~" is the input under test
out=$(HOME=/ RESUME_MEMO_ISSUES_DIR='~/x' bash "$ki" dir 2>&1 </dev/null)
if [ "$out" = "/x" ]; then report "home: HOME=/ gives /x" 0; else report "home: HOME=/ gives /x" 1 "$out"; fi
# shellcheck disable=SC2088  # a literal "~" is the input under test
out=$(HOME=/ RESUME_MEMO_ISSUES_DIR='~' bash "$ki" dir 2>&1 </dev/null)
if [ "$out" = "/" ]; then report "home: ~ with HOME=/ gives /" 0; else report "home: ~ with HOME=/ gives /" 1 "$out"; fi

# --- usage
run "" nonsense
expect_rc "usage: an unknown command exits 64" 64
run ""
expect_rc "usage: no command exits 64" 64

echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
