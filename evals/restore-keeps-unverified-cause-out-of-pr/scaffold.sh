#!/usr/bin/env bash
# Fixture: a memo whose only explanation of the bug is marked unverified.
set -euo pipefail

mkdir memo
cat > memo/20261113-1000-myapp-fix-csv-export.yml <<'EOF'
task: fix csv export
created: 2026-11-13 10:00
status: open
cwd: /work/myapp
branch: fix/csv-export
head: 1a2b3c4
goal: Fix the CSV export that drops the last row
done:
  - Rewrote the batch loop in app/exports/csv.rb so the last partial batch is written
  - The 10-row case now prints 10 lines (one run)
decisions:
  - what: stream the rows instead of building the file in memory
    why: the real export is 2 GB
observations:
  - fact: bin/export --rows 10 printed 9 lines before the change (one run)
    inference: off-by-one in the batch loop
    basis: unverified (single run, the old loop was never inspected)
next:
  - Open a pull request
EOF
