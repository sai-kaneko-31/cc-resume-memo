# cc-resume-memo

A Claude Code plugin that writes the working state which exists only in the conversation to a per-session YAML memo, so a fresh session can continue from the file alone.

`/compact` summarizes a conversation and `/clear` discards it. How a decision was reached, what was investigated and what failed can be lost or distorted either way. The `resume-memo` skill saves that state to a file before you run either one, and a session that reads the file can pick the work up again.

## What goes into a memo

- Decisions and the reasons for them ("why B and not A"), and approaches that were tried and failed.
- Observations (commands run, their output) as separate items from the inferences drawn from them. Each inference carries a `basis`, and an inference from a single observation is marked `unverified`.
- Open questions, the user's standing instructions, and numbered next steps.
- Not file contents, diffs, or secrets. Those can be recovered from disk or git, or should not be written at all.

```yaml
task: fix csv export
created: 2026-11-13 10:00
status: open
cwd: /work/myapp
branch: fix/csv-export
head: 1a2b3c4
goal: Fix the CSV export that drops the last row
decisions:
  - what: stream the rows instead of building the whole file in memory
    why: the failing export is 2 GB
    rejected: raising the memory limit
observations:
  - fact: export of 10 rows returns 9 rows
    inference: off-by-one in the batch loop
    basis: unverified
next:
  - add a failing test for the 10-row case
  - fix the batch loop in app/exports/csv.rb:42
```

## Install

```
/plugin marketplace add sai-kaneko-31/cc-resume-memo
/plugin install resume-memo@cc-resume-memo
```

## Use

Ask in plain words ("save the session state before I compact"), or run the skill directly with `/resume-memo:resume-memo`. Claude writes the memo, checks it, and tells you the path and a sentence to paste into the next session:

```
Read <full path> and resume the work
```

The skill does not run when you are only talking about compaction. It runs when you announce `/compact` or `/clear`, or ask to save or hand off the session.

Memos are written to `~/.claude/resume-memos/<YYYYMMDD-HHMM>-<project>-<task-slug>.yml`. Set `RESUME_MEMO_DIR` to use another directory. The hooks read the same variable.

## Known issues

The skill keeps a small log of its own failures, so the next run does not repeat them. It is separate from the memos: a memo is the state of one session, an entry is what to do differently next time.

- One file per failure: `~/.claude/resume-memos/known-issues/<slug>.md`. A file has a one-line `rule:`, a `case:` and a `prevention:`, plus `count`, `first_seen` and `last_seen`. A repeat of the same cause adds to the count and appends a `recurrence:` line instead of creating a second file.
- Before writing a memo, the skill runs `scripts/known-issue.sh list`. It prints one line per entry, the most repeated first, at most 20 lines, and nothing when there are no entries. The skill opens an entry's file only when the rule line is not enough.
- After a run in which a step failed or had to be redone, and the cause can happen again, the skill records it. A failure that the next command caught is not recorded.
- Only failures of this skill's own work (writing, checking, updating or restoring a memo) are recorded. This is not a log of everything that went wrong in a session, and the plugin writes nowhere outside its own directory.
- Entries are scanned for secret-like text before they are written, with the same patterns as the memo check. It is a safety net, not a guarantee. When an entry has been moved into your `CLAUDE.md` or into the skill's text, delete its file.

## The archive

A restore reads the whole memo, so finished items would cost tokens in every restore. Finished work goes to a second file that a restore does not read by default: `~/.claude/resume-memos/done/<same file name>`. That is the `done` steps, and the decisions and observations that belong to them. A memo then holds only what is needed to continue. That is what is in progress, what is next, the open questions, and the decisions and observations that those items still depend on.

- The `done/` directory is not matched by the pattern the hooks and the restore command use, so an archive is never listed as a memo.
- Each update moves what has just been finished into the archive. A superseded item is replaced in place, not kept under "Older note".
- The SessionStart hook prints the path of a memo's archive when one exists. The skill opens it only when you ask what was done, when a next step points at finished work, or before it adds items to it.
- A memo written before the archive existed keeps `done:` inline and restores as before. `check-memo.sh` prints a `Note:` for an open memo that still has `done` items, so they are moved when the memo is next updated.

## Hooks

- `SessionStart` with the `compact` matcher: after a compaction, prints the head (task, created, cwd, branch, head, goal) of the newest three open memos of the current project. Claude can then read the one that matches. A memo that has an archive also gets an `archive:` line with its path.
- `PreCompact`: prints instructions for the compaction summary, and the path of the newest open memo. The Claude Code hooks reference says a PreCompact hook's stdout is used as instructions for the summary. This plugin's effect on summaries has not been measured.

## The check script

`scripts/check-memo.sh <memo>` runs after a memo is written.

- It loads the YAML, and reports list items that YAML read as something other than text (a plain item containing `: ` becomes a mapping, and a bare `yes` becomes a boolean). The load succeeds in both cases, so only this check catches them.
- It scans for secret-like text (private key headers, GitHub, Slack and AWS keys, URLs with credentials, bearer tokens, `key=value` assignments) and names the pattern and the line, not the value. It is a safety net, not a guarantee.
- Exit codes: 0 ok, 1 YAML problem, 2 secret-like text, 3 YAML not checked because neither ruby nor python3 with PyYAML is installed.
- `--secrets-only <file>` scans any text file for secret-like text and does not load it as YAML (exit 0 or 2). `known-issue.sh` uses it on the entries it writes.
- A `Note:` line never changes the exit code. An open memo that still has `done` items gets one.
- It also checks an archive file (no header keys, no `status`).

## Requirements

- bash. Native Windows is not supported (WSL should work; it has not been tried).
- git with `rev-parse --path-format=absolute` for worktree-aware project names (tested with git 2.56.0). If that command fails, the scripts use the directory name as the project name; this fallback is not covered by the tests.
- For the YAML check: ruby, or python3 with PyYAML. Without either, the check still scans for secrets and the closing message says the YAML was not checked.

## Tests

```bash
bash tests/run.sh
shellcheck --severity=warning scripts/*.sh tests/*.sh
claude plugin validate .
```

The suite ran against Ruby 2.6.10 (the macOS system Ruby) and Python with PyYAML 6.0.3. A path whose runtime is missing is reported as `SKIP` and is untested.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE).
