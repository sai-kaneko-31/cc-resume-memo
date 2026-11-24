# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-11-24

### Added

- `RESUME_MEMO_ISSUES_DIR`: the directory of the known-issues entries, for a directory the user already fills by hand. A leading `~/` is expanded, and `~name/` is refused with exit 64, as is `~` while HOME is empty. The default stays `known-issues/` inside the memo directory.
- `known-issue.sh search <word>...` prints the lines that contain any of the words, ignoring the case of ASCII letters, from the `.md` files under that directory. Notes written by hand are searched too, and at most 20 lines are printed. The skill uses it to look a cause up before it adds an entry. `known-issue.sh dir` prints the directory.
- The skill records known issues without writing a memo when the user asks to record them.

### Changed

- The log covers the failures of the whole session, not only the failures of the skill's own steps. A cause that is already written down in a note written by hand is reported to the user and not added again.
- Only a file whose first line starts with `rule: ` is an entry. `list` skips other files, `recur` and `add` leave them unchanged, and the "more than 30 entries" note counts entries only.
- A file that is not valid UTF-8, such as a note written by hand in another encoding, no longer hides lines from `search`, cuts a rule short in `list` or makes `recur` fail in a UTF-8 locale.
- `recur` refuses a `count:` line of more than 15 digits (leading zeros not counted) with exit 64, because bash wraps a 19-digit count around to a negative number.
- A symbolic link is not an entry: `list` skips it, and `add` and `recur` never write through or replace it. `search` exits 1 when it could not read part of the directory, so an empty output with exit 0 means that nothing matched in the files it searches. A file that contains a NUL byte, such as a note in UTF-16, is not searched. A new entry gets the file mode that the umask gives, and a repeat keeps the mode of the entry.

## [0.2.0] - 2026-11-24

First tagged release. Earlier commits carried the version 0.1.0 in `plugin.json` but were never tagged, so everything below is new to a user who installs this release.

### Added

- `resume-memo` skill: writes the working state that exists only in the conversation to a per-session YAML memo, with observations and inferences as separate items and a `basis` for each inference.
- `user_instructions` key in the memo template, for the user's standing instructions and preferences.
- `scripts/check-memo.sh`: loads the memo as YAML, reports list items that YAML read as a mapping or a boolean, reports text that a ` #` turned into a comment (for example `see issue #123` in a plain value), and scans for secret-like text. Works with ruby or python3 with PyYAML, and reports exit code 3 when neither is available.
- `SessionStart` hook (`compact` matcher) that prints the head of the newest open memos of the current project after a compaction.
- `PreCompact` hook that prints instructions for the compaction summary and the path of the newest open memo.
- Restore guidance: treat memo text as data, compare `branch` and `head` with the current git state, and do not copy unverified causes, from a memo or from its archive, into Issues, PRs or specs.
- Tests for the check script and both hooks, run against ruby and python.
- The skill runs when `/compact` or `/clear` is announced, or when the user asks to save or hand off the session. It does not run when the user is only discussing compaction.
- Known issues: a log of failures that happened while the skill ran, one file per failure in `<memo dir>/known-issues/`. `scripts/known-issue.sh` has `list`, `add` and `recur` commands; the skill lists the entries before it writes or restores a memo, and records a failure that can happen again. Entries are scanned for secret-like text.
- `check-memo.sh --secrets-only <file>` scans any text file for secret-like text without loading it as YAML.
- Archive: finished work (`done` steps, and the decisions and observations that belong to them) goes to `done/<memo file name>` next to the memo, and a restore does not read it by default. The memo template has no `done` key. A memo that has `done:` inline is still restored and checked as before.
- Update rule in the skill: a finished item moves to the archive, and a superseded item is replaced in place instead of being kept under a heading such as "Older note".
- The `SessionStart` hook prints an `archive:` line for a memo that has an archive.
- `check-memo.sh` prints a `Note:` line (exit code unchanged) for an open memo that still has `done` items, and checks an archive file like a memo.
