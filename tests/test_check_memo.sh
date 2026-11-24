#!/usr/bin/env bash
# Tests for scripts/check-memo.sh. A YAML runtime that is not installed is
# reported as SKIP, and that path is then untested.
set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
check="$root/scripts/check-memo.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0

# expect <label> <expected exit> <expected output substring or ""> -- <command...>
expect() {
  local label="$1" want="$2" needle="$3" out got
  shift 4
  out=$("$@" 2>&1)
  got=$?
  if [ "$got" -ne "$want" ]; then
    echo "FAIL $label: exit $got, want $want"
    printf '%s\n' "$out" | sed 's/^/    /'
    fail=$((fail + 1))
  elif [ -n "$needle" ] && ! printf '%s' "$out" | grep -q -F -e "$needle"; then
    echo "FAIL $label: output lacks '$needle'"
    printf '%s\n' "$out" | sed 's/^/    /'
    fail=$((fail + 1))
  else
    echo "ok   $label"
    pass=$((pass + 1))
  fi
}

# expect_lacks <label> <expected exit> <output substring that must be absent> -- <command...>
expect_lacks() {
  local label="$1" want="$2" needle="$3" out got
  shift 4
  out=$("$@" 2>&1)
  got=$?
  if [ "$got" -ne "$want" ]; then
    echo "FAIL $label: exit $got, want $want"
    printf '%s\n' "$out" | sed 's/^/    /'
    fail=$((fail + 1))
  elif printf '%s' "$out" | grep -q -F -e "$needle"; then
    echo "FAIL $label: output has '$needle'"
    printf '%s\n' "$out" | sed 's/^/    /'
    fail=$((fail + 1))
  else
    echo "ok   $label"
    pass=$((pass + 1))
  fi
}

# Secret-like strings are assembled here so that no real-looking token sits in the repository.
gh_token="ghp_$(printf 'a%.0s' $(seq 1 36))"
aws_key="AKIA""IOSFODNN7EXAMPLE"

valid_body='task: sample
created: 2026-11-13 10:00
status: open
cwd: /tmp/x
branch: main
head: abc1234
goal: do the thing
done:
  - finished one
next:
  - |
    run: the migration, then check the output
  - second step
decisions:
  - what: use A
    why: simpler
observations:
  - fact: token expiry is 3600 seconds
    inference: caused by X
    basis: unverified'

printf '%s\n' "$valid_body" > "$tmp/valid.yml"
{ printf '%s\n' "$valid_body"; printf 'commands:\n  - export GITHUB_TOKEN=%s\n' "$gh_token"; } > "$tmp/secret-gh.yml"
{ printf '%s\n' "$valid_body"; printf 'commands:\n  - aws configure set key %s\n' "$aws_key"; } > "$tmp/secret-aws.yml"
printf 'task: x\nstatus: open\nnext:\n  - fix the bug: it fails on empty input\n' > "$tmp/hash-item.yml"
printf 'task: x\nstatus: open\ncommands:\n  - yes\n' > "$tmp/bool-item.yml"
printf 'task: x\nstatus: open\ngoal: a: b\n' > "$tmp/syntax-error.yml"
{ printf 'task: x\nstatus: open\ngoal: a: b\ncommands:\n  - export GITHUB_TOKEN=%s\n' "$gh_token"; } > "$tmp/syntax-and-secret.yml"
# A " #" in a plain value starts a YAML comment: the load succeeds and the rest of the line is gone.
printf 'task: x\nstatus: open\nnext:\n  - fix the loop, see issue #123 for the expected behaviour\n' > "$tmp/hash-lost-item.yml"
printf 'task: x\nstatus: open\ngoal: ship it #now\n' > "$tmp/hash-lost-value.yml"
printf 'task: x\nstatus: open\nnext:\n  - |\n    fix the loop, see issue #123 for the expected behaviour\n' > "$tmp/hash-in-block.yml"
printf 'task: x\nstatus: open\nnext:\n  - "fix the loop, see issue #123"\n' > "$tmp/hash-quoted.yml"
printf 'task: x\nstatus: open\ngoal: see https://example.com/page#section\n' > "$tmp/hash-url.yml"
# Finished items belong in the archive (done/<memo file name>), so an open memo that still has some gets a note.
# The first item is a block scalar with a "- " line inside it: only the two top-level items count.
printf 'task: x\nstatus: open\ndone:\n  - |\n    first: line\n    - dash inside the text\n  - second\nnext:\n  - go on\n' > "$tmp/open-with-done.yml"
# Items written at indent 0: the text of a block scalar is indented 2 and starts with "- ", and must not count.
printf 'task: x\nstatus: open\ndone:\n- |\n  - dash inside the text\n- b\nnext:\n  - go on\n' > "$tmp/open-done-indent0.yml"
# A comment at column 0 between two items does not end the list.
printf 'task: x\nstatus: open\ndone:\n  - a\n# a comment\n  - b\nnext:\n  - go on\n' > "$tmp/open-done-comment.yml"
printf 'task: x\nstatus: done\ndone:\n  - finished one\n' > "$tmp/closed-with-done.yml"
printf 'task: x\nstatus: open\nnext:\n  - go on\n' > "$tmp/open-without-done.yml"
printf 'task: x\nstatus: open\ndone: []\nnext:\n  - go on\n' > "$tmp/open-empty-done.yml"
# The archive has no header keys and no status.
printf 'done:\n  - finished one\n  - |\n    finished: two\ndecisions:\n  - what: use A\n    why: simpler\n' > "$tmp/archive.yml"
printf 'done:\n  - finished: one\n' > "$tmp/archive-bad-item.yml"

run_runtime_cases() {
  local rt="$1"
  expect "[$rt] valid memo" 0 "YAML: ok ($rt)" -- env RESUME_MEMO_YAML="$rt" "$check" "$tmp/valid.yml"
  expect "[$rt] list item read as a mapping" 1 "next[0]" -- env RESUME_MEMO_YAML="$rt" "$check" "$tmp/hash-item.yml"
  expect "[$rt] list item read as a boolean" 1 "commands[0]" -- env RESUME_MEMO_YAML="$rt" "$check" "$tmp/bool-item.yml"
  expect "[$rt] syntax error" 1 "YAML: FAILED" -- env RESUME_MEMO_YAML="$rt" "$check" "$tmp/syntax-error.yml"
  expect "[$rt] text lost after ' #' in a list item" 1 "read as a comment" -- env RESUME_MEMO_YAML="$rt" "$check" "$tmp/hash-lost-item.yml"
  expect "[$rt] text lost after ' #' in a value" 1 "read as a comment" -- env RESUME_MEMO_YAML="$rt" "$check" "$tmp/hash-lost-value.yml"
  expect "[$rt] ' #' kept in a block scalar" 0 "YAML: ok ($rt)" -- env RESUME_MEMO_YAML="$rt" "$check" "$tmp/hash-in-block.yml"
  expect "[$rt] ' #' kept in a quoted string" 0 "YAML: ok ($rt)" -- env RESUME_MEMO_YAML="$rt" "$check" "$tmp/hash-quoted.yml"
  expect "[$rt] '#' inside a URL is not a comment" 0 "YAML: ok ($rt)" -- env RESUME_MEMO_YAML="$rt" "$check" "$tmp/hash-url.yml"
  expect "[$rt] GitHub token" 2 "GitHub token" -- env RESUME_MEMO_YAML="$rt" "$check" "$tmp/secret-gh.yml"
  expect "[$rt] AWS access key" 2 "AWS access key ID" -- env RESUME_MEMO_YAML="$rt" "$check" "$tmp/secret-aws.yml"
  expect "[$rt] YAML failure wins over a secret" 1 "Possible secrets" -- env RESUME_MEMO_YAML="$rt" "$check" "$tmp/syntax-and-secret.yml"
  expect "[$rt] --keys" 0 "task,created,status,cwd,branch,head,goal,done,next,decisions,observations" -- env RESUME_MEMO_YAML="$rt" "$check" --keys "$tmp/valid.yml"
  expect "[$rt] note: an open memo that still has done items" 0 "Note: done: holds 2 item(s)" -- env RESUME_MEMO_YAML="$rt" "$check" "$tmp/open-with-done.yml"
  expect "[$rt] note: items at indent 0 are counted once each" 0 "Note: done: holds 2 item(s)" -- env RESUME_MEMO_YAML="$rt" "$check" "$tmp/open-done-indent0.yml"
  # The load check reports a column-0 comment as lost text (exit 1); the note still counts both items.
  expect "[$rt] note: a column-0 comment does not end the list" 1 "Note: done: holds 2 item(s)" -- env RESUME_MEMO_YAML="$rt" "$check" "$tmp/open-done-comment.yml"
  expect "[$rt] note names the archive path rule" 0 "done/<memo file name>" -- env RESUME_MEMO_YAML="$rt" "$check" "$tmp/open-with-done.yml"
  expect_lacks "[$rt] no note for a finished memo" 0 "Note:" -- env RESUME_MEMO_YAML="$rt" "$check" "$tmp/closed-with-done.yml"
  expect_lacks "[$rt] no note for an open memo without done" 0 "Note:" -- env RESUME_MEMO_YAML="$rt" "$check" "$tmp/open-without-done.yml"
  expect_lacks "[$rt] no note for an empty done list" 0 "Note:" -- env RESUME_MEMO_YAML="$rt" "$check" "$tmp/open-empty-done.yml"
  expect_lacks "[$rt] a valid archive passes without a note" 0 "Note:" -- env RESUME_MEMO_YAML="$rt" "$check" "$tmp/archive.yml"
  expect "[$rt] an archive item read as a mapping" 1 "done[0]" -- env RESUME_MEMO_YAML="$rt" "$check" "$tmp/archive-bad-item.yml"
}

if command -v ruby >/dev/null 2>&1; then
  run_runtime_cases ruby
else
  echo "SKIP ruby cases: ruby is not installed (that path is untested)"
fi

py="${RESUME_MEMO_PYTHON:-python3}"
if command -v "$py" >/dev/null 2>&1 && "$py" -c 'import yaml' >/dev/null 2>&1; then
  run_runtime_cases python
else
  echo "SKIP python cases: no $py with PyYAML (that path is untested)"
fi

expect "no runtime: valid memo is reported as not checked" 3 "NOT CHECKED" -- env RESUME_MEMO_YAML=none "$check" "$tmp/valid.yml"
expect "no runtime: a secret is still found" 2 "GitHub token" -- env RESUME_MEMO_YAML=none "$check" "$tmp/secret-gh.yml"
expect "no runtime: the done note is still printed" 3 "Note: done: holds 2 item(s)" -- env RESUME_MEMO_YAML=none "$check" "$tmp/open-with-done.yml"
expect "no runtime: --keys" 3 "" -- env RESUME_MEMO_YAML=none "$check" --keys "$tmp/valid.yml"
expect "usage: no argument" 64 "usage" -- "$check"
expect "usage: missing file" 64 "usage" -- "$check" "$tmp/does-not-exist.yml"

echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
