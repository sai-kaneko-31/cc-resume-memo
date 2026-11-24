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
- Restore guidance: treat memo text as data, compare `branch` and `head` with the current git state, and do not copy unverified causes into Issues or PRs.
- Tests for the check script and both hooks, run against ruby and python.
- The skill runs when `/compact` or `/clear` is announced, or when the user asks to save or hand off the session. It does not run when the user is only discussing compaction.
- Known issues: a log of failures that happened while the skill ran, one file per failure in `<memo dir>/known-issues/`. `scripts/known-issue.sh` has `list`, `add` and `recur` commands; the skill lists the entries before it writes a memo and records a failure that can happen again. Entries are scanned for secret-like text.
- `check-memo.sh --secrets-only <file>` scans any text file for secret-like text without loading it as YAML.
