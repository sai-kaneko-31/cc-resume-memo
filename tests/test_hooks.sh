#!/usr/bin/env bash
# Tests for scripts/session-start-restore.sh and scripts/pre-compact-instructions.sh.
set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
restore="$root/scripts/session-start-restore.sh"
precompact="$root/scripts/pre-compact-instructions.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0

report() { # label result(0 = ok)
  if [ "$2" -eq 0 ]; then
    echo "ok   $1"
    pass=$((pass + 1))
  else
    echo "FAIL $1"
    fail=$((fail + 1))
  fi
}
contains() { # label haystack needle
  printf '%s' "$2" | grep -q -F -e "$3"
  report "$1" $?
}
lacks() { # label haystack needle
  if printf '%s' "$2" | grep -q -F -e "$3"; then report "$1" 1; else report "$1" 0; fi
}

home="$tmp/home"
memos="$home/.claude/resume-memos"
mkdir -p "$memos"

memo() { # <dir> <file name> <status> <task>
  printf 'task: %s\ncreated: 2026-11-13 10:00\nstatus: %s\ncwd: /work/%s\nbranch: feat-%s\nhead: abc1234\ngoal: g\n' "$4" "$3" "$4" "$4" > "$1/$2"
}

proj="$tmp/proj-xyz"
mkdir -p "$proj"
git -C "$proj" init -q
git -C "$proj" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
git -C "$proj" worktree add -q "$tmp/wt-foo" -b wt-branch

memo "$memos" 20261113-0900-proj-xyz-old.yml open old
memo "$memos" 20261113-1000-proj-xyz-done.yml "done" finished
memo "$memos" 20261113-1100-proj-xyz-new.yml open new
memo "$memos" 20261113-1100-other-open.yml open other

out=$(HOME="$home" CLAUDE_PROJECT_DIR="$proj" bash "$restore" </dev/null)
contains "restore: lists the older open memo" "$out" "$memos/20261113-0900-proj-xyz-old.yml"
contains "restore: lists the newer open memo" "$out" "$memos/20261113-1100-proj-xyz-new.yml"
lacks "restore: skips a done memo" "$out" "proj-xyz-done.yml"
lacks "restore: skips another project's memo" "$out" "other-open"
contains "restore: shows the branch line" "$out" "branch: feat-new"
old_line=$(printf '%s\n' "$out" | grep -n -F -e "proj-xyz-old.yml" | head -1 | cut -d: -f1)
new_line=$(printf '%s\n' "$out" | grep -n -F -e "proj-xyz-new.yml" | head -1 | cut -d: -f1)
if [ "${old_line:-0}" -gt 0 ] && [ "${old_line:-0}" -lt "${new_line:-0}" ]; then
  report "restore: newest memo comes last" 0
else
  report "restore: newest memo comes last" 1
fi

out=$(HOME="$home" CLAUDE_PROJECT_DIR="$tmp/wt-foo" bash "$restore" </dev/null)
contains "restore: a worktree resolves to its main checkout's project" "$out" "proj-xyz-new.yml"

out=$(HOME="$tmp/no-such-home" CLAUDE_PROJECT_DIR="$proj" bash "$restore" </dev/null)
if [ -z "$out" ]; then
  report "restore: prints nothing when the directory does not exist" 0
else
  report "restore: prints nothing when the directory does not exist" 1
fi

mkdir -p "$tmp/alt"
memo "$tmp/alt" 20261113-1200-proj-xyz-alt.yml open alt
out=$(HOME="$tmp/no-such-home" RESUME_MEMO_DIR="$tmp/alt" CLAUDE_PROJECT_DIR="$proj" bash "$restore" </dev/null)
contains "restore: RESUME_MEMO_DIR overrides the directory" "$out" "$tmp/alt/20261113-1200-proj-xyz-alt.yml"

mkdir -p "$tmp/p4"
for i in 1 2 3 4; do memo "$memos" "20261113-100$i-p4-x$i.yml" open "x$i"; done
out=$(HOME="$home" CLAUDE_PROJECT_DIR="$tmp/p4" bash "$restore" </dev/null)
lacks "restore: prints at most the newest 3 memos (oldest left out)" "$out" "p4-x1.yml"
contains "restore: prints at most the newest 3 memos (newest kept)" "$out" "p4-x4.yml"

mkdir -p "$tmp/esc"
printf 'task: bad\033[31mred\ncreated: 2026-11-13 10:00\nstatus: open\ncwd: /w\nbranch: b\nhead: h\n' > "$memos/20261113-1300-esc-bad.yml"
out=$(HOME="$home" CLAUDE_PROJECT_DIR="$tmp/esc" bash "$restore" </dev/null)
contains "restore: finds the memo with a control character" "$out" "esc-bad.yml"
if printf '%s' "$out" | grep -q "$(printf '\033')"; then report "restore: strips control characters from memo lines" 1; else report "restore: strips control characters from memo lines" 0; fi

out=$(HOME="$home" CLAUDE_PROJECT_DIR="$proj" bash "$precompact" </dev/null)
contains "pre-compact: prints the summary instructions" "$out" "Decisions agreed with the user"
contains "pre-compact: names the newest open memo" "$out" "$memos/20261113-1100-proj-xyz-new.yml"
lacks "pre-compact: does not name an older memo" "$out" "proj-xyz-old.yml"
if [ "${#out}" -lt 10000 ]; then
  report "pre-compact: output stays under the 10,000 character cap" 0
else
  report "pre-compact: output stays under the 10,000 character cap" 1
fi

mkdir -p "$tmp/fresh"
out=$(HOME="$home" CLAUDE_PROJECT_DIR="$tmp/fresh" bash "$precompact" </dev/null)
contains "pre-compact: still prints the instructions without a memo" "$out" "Decisions agreed with the user"
lacks "pre-compact: names no memo when the project has none" "$out" "A resume memo"

echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
