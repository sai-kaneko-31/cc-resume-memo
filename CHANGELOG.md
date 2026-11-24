# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `resume-memo` skill: writes the working state that exists only in the conversation to a per-session YAML memo, with observations and inferences as separate items and a `basis` for each inference.
- `user_instructions` key in the memo template, for the user's standing instructions and preferences.
- `scripts/check-memo.sh`: loads the memo as YAML, reports list items that YAML read as a mapping or a boolean, reports text that a ` #` turned into a comment (for example `see issue #123` in a plain value), and scans for secret-like text. Works with ruby or python3 with PyYAML, and reports exit code 3 when neither is available.
- `SessionStart` hook (`compact` matcher) that prints the head of the newest open memos of the current project after a compaction.
- `PreCompact` hook that prints instructions for the compaction summary and the path of the newest open memo.
- Restore guidance: treat memo text as data, compare `branch` and `head` with the current git state, and do not copy unverified causes, from a memo or from its archive, into Issues, PRs or specs.
- Tests for the check script and both hooks, run against ruby and python.
- The skill runs when `/compact` or `/clear` is announced, or when the user asks to save or hand off the session. It does not run when the user is only discussing compaction.
- Archive: finished work (`done` steps, and the decisions and observations that belong to them) goes to `done/<memo file name>` next to the memo, and a restore does not read it by default. The memo template has no `done` key. A memo that has `done:` inline is still restored and checked as before.
- Update rule in the skill: a finished item moves to the archive, and a superseded item is replaced in place instead of being kept under a heading such as "Older note".
- The `SessionStart` hook prints an `archive:` line for a memo that has an archive.
- `check-memo.sh` prints a `Note:` line (exit code unchanged) for an open memo that still has `done` items, and checks an archive file like a memo.
