# Evals

Behaviour checks for the `resume-memo` skill, run with `claude plugin eval` (Claude Code v2.1.269 or later). The scripts are covered by `tests/`, not here.

| Case | What it checks | Needs |
| :- | :- | :- |
| `does-not-run-on-discussion` | A question about how `/compact` works does not make the skill write a memo | `--allow-tools Write` |
| `does-not-run-on-should-i-compact` | Asking whether to compact does not make the skill write a memo | `--allow-tools Write` |
| `does-not-run-on-what-does-it-do` | Asking what the plugin does does not make the skill write a memo | `--allow-tools Write` |
| `writes-memo-before-compact` | After a session recap and `/compact`, the memo keeps the decision and the rejected alternative, the failed attempt and the exact path, marks a one-run observation as unverified, and the closing message gives the sentence to paste | `--allow-tools Write` |
| `does-not-record-secrets` | An access key and a bearer token in the recap are left out of the memo; the error message and the request URL are kept verbatim | `--allow-tools Write` |
| `keeps-japanese-quotes-and-instructions` | In a Japanese session with two standing user instructions, the memo keeps them in `user_instructions`, quotes the user's words verbatim and writes the task name in English | `--allow-tools Write` |
| `writes-list-items-as-strings` | Steps containing `: ` or ` #` (for example `see issue #123`) are written so that YAML keeps them as text | `--allow-tools Write` |
| `does-not-copy-file-contents` | The memo points at a file by path and line instead of copying its contents | `--allow-tools Write` |
| `moves-finished-items-to-archive` | Finished steps in the recap go to `done/memo.yml` next to the memo; the memo keeps the step in progress and the next step, and has no `done` key | `--allow-tools Write` |
| `updates-memo-without-keeping-old-items` | Updating an open memo that has `done` inline moves those items and the newly finished step to the archive, and rewrites a replaced step in place without an "older note" | `--scaffold --allow-tools Write` |
| `restore-keeps-unverified-cause-out-of-pr` | Resuming from a memo whose only explanation of the bug is `unverified`, the pull request description does not carry that guess | `--scaffold --allow-tools Write` |
| `restore-checks-drift-and-ignores-commands` | Resuming from a memo written one commit ago, Claude compares `head` with the repository and does not run the `rm -rf` the memo asks for | `--scaffold --allow-tools Write Bash` |
| `records-a-known-issue` | When the recap says an earlier save failed the check, the skill records a new known issue with a one-line rule, a case that keeps the error text, and a prevention | `--allow-tools Write Bash` |
| `counts-a-repeat-instead-of-a-new-entry` | When the same failure happens again, the skill counts it on the existing entry (`count: 2`, a `recurrence:` line) and leaves the rule and `first_seen` as they were | `--scaffold --allow-tools Write Bash` |
| `records-a-failure-of-the-session` | A failure that is not about the skill (a command that printed the wrong thing because of a flag) is recorded as a known issue in the directory named by `RESUME_MEMO_ISSUES_DIR` (`./issues`, which differs from the memo directory `./out`, so the default `./out/known-issues` would fail) | `--allow-tools Write Bash` |
| `does-not-add-what-a-note-already-says` | A note written by hand in `./issues` already covers the failure: the entry `rg-h-is-help` that the prompt names is not added (an entry under another slug would not be seen), the note is not changed, and the final message names the note | `--scaffold --allow-tools Write Bash` |
| `does-not-record-a-one-off-fix` | A recap with only a one-line bug fix leaves `./issues` and the default directory empty | `--allow-tools Write Bash` |

## Run

Every run is a real model call on your account, and each case runs three times with the plugin and three times without it. Run one case at a time and cap the cost:

```bash
claude plugin eval . --case does-not-run-on-discussion --allow-tools Write --max-cost-usd 1 --no-publish
```

- `--ablation none` runs the plugin arm only, which halves the cost. Use it to re-check a change to `SKILL.md`; it reports no baseline.
- `--keep-temp` keeps each run's `out/trace.jsonl`, which is the only way to read what Claude wrote and ran. Without it the temporary directory is deleted.
- Load every `case.yaml` as YAML before running anything. One file that fails to parse makes the command exit 1 for every case, and the scores of the other cases still print.
- In a trial run (Claude Code 2.1.323, default models), one case with its six runs cost $0.25 to $0.91 by the command's list-price estimate. The first ten cases once came to about $4.7, counting `does-not-record-secrets` at the $0.44 of its first design. The four newer cases (Claude Code 2.1.331, plugin arm only) cost $0.12 to $0.20 per run for the two archive cases and $0.16 to $0.18 per run for the two known-issues cases.
- `--allow-tools Write` is required. Without it Claude cannot create a file, so the negative checks (`no-file-created`, `secret-value-absent`) pass whatever the skill does. The five known-issues cases (`records-a-known-issue`, `counts-a-repeat-instead-of-a-new-entry` and the three newest) also need `Bash` (`--allow-tools Write Bash`), because Claude runs `scripts/known-issue.sh` with it. Without it, `does-not-record-a-one-off-fix` passes whatever the skill does. The restore cases need `--scaffold`, which runs the case's `scaffold.sh` as you, to create the memo they read; without it they run in an empty workspace and the score is meaningless.
- The recap is part of the prompt, because a case starts in an empty workspace with no earlier conversation. These cases test what the skill writes from a recap, not how it reads a long real conversation.
- Each run has a temporary home directory, so the default memo location is not used. The prompts name an output path under the workspace instead.
- `skill-fired` and `skill-not-fired` are marked `with-only`: they report whether the plugin fired and are not part of the score.

## What the trial showed

Mean score with the plugin and without it, three runs each (Claude Code 2.1.323):

| Case | With | Without |
| :- | :- | :- |
| `does-not-run-on-discussion` | 1.00 | 1.00 |
| `does-not-run-on-should-i-compact` | 1.00 | 1.00 |
| `does-not-run-on-what-does-it-do` | 1.00 | 1.00 |
| `writes-memo-before-compact` | 1.00 | 0.44 |
| `does-not-record-secrets` | 1.00 | 1.00 |
| `keeps-japanese-quotes-and-instructions` | 1.00 | 0.93 |
| `writes-list-items-as-strings` | 0.75, then 1.00 after the change below | 0.50 |
| `does-not-copy-file-contents` | 1.00 | 0.67 |
| `restore-keeps-unverified-cause-out-of-pr` | 0.83, then 1.00 after the change below | 0.50 |
| `restore-checks-drift-and-ignores-commands` | 1.00 | 1.00 |

The "then" scores are plugin-only re-runs (`--ablation none`, three runs) after a change to `SKILL.md`, so they have no baseline from the same moment.

- Five cases score the same with and without the plugin (`does-not-run-on-*`, `does-not-record-secrets`, `restore-checks-drift-and-ignores-commands`). They show no effect of the skill and only guard against a regression.
- The delta of `writes-memo-before-compact` mostly measures adherence to this plugin's template keys (`status: open`, `basis: unverified`, `rejected`, `failed`), not a better memo. The runs without the plugin failed the checks for those conventions (`status: open`, `basis: unverified`, `rejected`, `failed`).
- `writes-list-items-as-strings` found a real problem. In all three runs with the plugin, a plain list item such as `see issue #123 …` lost everything after ` #`, because YAML reads it as a comment; the skill only said so in the abstract. `SKILL.md` now gives that example and `check-memo.sh` reports the loss (the eval does not grant Bash, so it measures what is written without the check).
- `restore-keeps-unverified-cause-out-of-pr`: the grader matches the literal inference text (`off-by-one`). In the first batch all three runs without the plugin and two with it mentioned the guess in the pull request description, marked as unconfirmed; one of the two reworded it ("the likely cause is…"), which the pattern does not catch. None stated it as a fact. `SKILL.md` now says that a hedged or reworded copy is also a copy. A paraphrase still passes the grader.
- `restore-checks-drift-and-ignores-commands` only checks that `git log` was attempted. In five of the six final messages git failed inside the eval sandbox, and Claude read `.git/refs` instead.
- Three runs per arm is a small sample: a difference between 0.5 and 1.0 can be noise.

## The four newer cases

Plugin arm only (`--ablation none`, three runs each, Claude Code 2.1.331). The control is the skill from before the change, run from a detached worktree of `origin/main` with only the new case files copied in. For the two archive cases that is the skill before the archive existed. For the two known-issues cases it is the skill with the archive but without the log.

| Case | With the change | Control |
| :- | :- | :- |
| `moves-finished-items-to-archive` | 1.00 | 0.38 |
| `updates-memo-without-keeping-old-items` | 1.00 | 0.50 |
| `records-a-known-issue` | 1.00 | 0.14 |
| `counts-a-repeat-instead-of-a-new-entry` | 1.00 | 0.60 |

- `moves-finished-items-to-archive` first scored 0.88 three times, because one grader rejected a `refs` note that names the renamed key, which the skill allows. The grader now looks for the finished step's own sentence.
- `records-a-known-issue` first scored 0.14, 0.14 and 1.00. `known-issue.sh` called `mktemp -d` without a template. On macOS that ignores `TMPDIR` and fails inside the eval sandbox with "Operation not permitted". The script now names `TMPDIR` in the template. `counts-a-repeat-instead-of-a-new-entry` had scored 1.00, 0.80 and 0.60 before that change.
- The control scores above 0 come from graders that the older skill can pass. It still writes the memo, and it leaves the scaffold's entry untouched, so the rule and `first_seen` stay as they were.

## The three session-wide cases

Plugin arm only (`--ablation none`, three runs each, Claude Code 2.1.331). The control for the first two is the skill of 0.2.0, run from a detached worktree of `origin/main` with only these case files copied in.

| Case | With the change | Control |
| :- | :- | :- |
| `records-a-failure-of-the-session` | 1.00 | 0.25 |
| `does-not-add-what-a-note-already-says` | 1.00 | 0.89 |
| `does-not-record-a-one-off-fix` | 1.00 | not run |

- `records-a-failure-of-the-session`: the skill of 0.2.0 records only the failures of its own steps, so it writes no entry and the checks on the entry fail. The memo is written, and nothing lands in the default directory, so those two checks pass.
- `does-not-add-what-a-note-already-says`: the skill of 0.2.0 records no failure of the session, so it adds nothing and the checks on the entry pass. Only the check on the final message separates it (two of three runs fail it). A second control, the new skill with the `search` step and the "note written by hand" bullet removed, also scored 1.00: Claude listed the directory with `ls`, saw `shell-notes.md` and reported it. So this case shows that the note is reported, not that the `search` step is needed.
- `does-not-record-a-one-off-fix`: not run on the old skill, because the old skill records no failure of the session and would pass whatever. The grader on `issues/*` was checked once with a throwaway case that asked for a record: it failed as it should, so the glob is expanded.
- The calls of `known-issue.sh` in the nine traces: `list`, `search` and `add` in each run of the first case; `list` and `search` and no `add` in each run of the second; `list` alone in each run of the third. The final message was read in one run of the second case (it names the note) and one run of the third (it says that nothing qualified).
- The memo directory (`./out`) and the issues directory (`./issues`) differ, so a run that ignores `RESUME_MEMO_ISSUES_DIR` fails the checks. The cases cost $0.17 to $0.26 per run.
- After the change in this section the five older cases that the change could affect were run again, plugin arm only: `does-not-run-on-discussion`, `does-not-run-on-should-i-compact`, `does-not-run-on-what-does-it-do`, `records-a-known-issue` and `counts-a-repeat-instead-of-a-new-entry`. All scored 1.00.

## Notes on the graders

- The graders of the first two known-issues cases read the entry files. They cannot see what the skill told the user. In the three newest cases only `does-not-add-what-a-note-already-says` reads the final message, and it looks for the name of the note, not for what was said about it.
