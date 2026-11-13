# Contributing

Thanks for your interest. Issues and pull requests are welcome.

## Before you open a pull request

1. Fork the repository and create a branch from `main`, for example `git checkout -b fix/check-memo-bool`.
2. Make the change. A change to a script needs a test in `tests/`; write the test first and watch it fail.
3. Run the checks (there is no CI yet, so this is the only gate):

   ```bash
   bash tests/run.sh
   shellcheck --severity=warning scripts/*.sh tests/*.sh
   claude plugin validate .
   ```

   A line reported as `SKIP` means that runtime is not installed on your machine and its path was not tested. Say so in the pull request.
4. Open the pull request against `main` with a description of what changes and why.

## Commit messages

This project uses [Conventional Commits](https://www.conventionalcommits.org/), in English:

```
feat: add a user_instructions key to the memo template
fix: report a bare yes in a list item as a boolean
docs: explain RESUME_MEMO_DIR in the README
test: cover a worktree path in the restore hook
chore: ignore .DS_Store
ci: run the tests on ubuntu-latest
```

- The subject is imperative and at most 72 characters. Put the reason in the body when it is not obvious.
- Pull requests are squash-merged, and the pull request title becomes the commit subject, so write the title in the same form (`type: subject`).
- Breaking changes use `!` after the type (`feat!: rename the memo directory`) and a `BREAKING CHANGE:` footer.

## Changelog and versions

`CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/). Add a line under `Unreleased` for any change a user would notice. Versions follow [Semantic Versioning](https://semver.org/). `version` in `.claude-plugin/plugin.json` is bumped on release only: Claude Code keeps users on the version that is set until it changes.

## What not to put in the repository

Memos, test fixtures and examples must not contain real tokens, personal data, or other people's text. Build secret-like strings in the test at run time, as `tests/test_check_memo.sh` does.

## Licence

By contributing, you agree that your contributions are licensed under the MIT License of this project.
