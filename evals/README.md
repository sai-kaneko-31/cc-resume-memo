# Evals

Behaviour checks for the `resume-memo` skill, run with `claude plugin eval` (Claude Code v2.1.269 or later). The scripts are covered by `tests/`, not here.

| Case | What it checks |
| :- | :- |
| `does-not-run-on-discussion` | A question about how `/compact` works does not make the skill write a memo |
| `writes-memo-before-compact` | After a session recap and `/compact`, the memo keeps the decision and the rejected alternative, the failed attempt and the exact path, and marks a one-run observation as unverified |
| `does-not-record-secrets` | A credential in the recap is left out of the memo, and the error message is kept verbatim |

## Run

Every run is a real model call on your account, and each case runs three times with the plugin and three times without it. Run one case at a time and cap the cost:

```bash
claude plugin eval . --case does-not-run-on-discussion --allow-tools Write --max-cost-usd 1 --no-publish
```

- `--allow-tools Write` is required. Without it Claude cannot create a file, so the negative checks (`no-file-created`, `secret-value-absent`) pass whatever the skill does.
- The recap is part of the prompt, because a case starts in an empty workspace with no earlier conversation. These cases test what the skill writes from a recap, not how it reads a long real conversation.
- Each run has a temporary home directory, so the default memo location is not used. The prompts name an output path under the workspace instead.
- `skill-fired` and `skill-not-fired` are marked `with-only`: they report whether the plugin fired and are not part of the score.
