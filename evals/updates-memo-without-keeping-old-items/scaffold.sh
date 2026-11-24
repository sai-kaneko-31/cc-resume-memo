#!/usr/bin/env bash
# Fixture: an open memo written before the archive existed (finished work inline under done),
# with a step in progress and two next steps.
set -euo pipefail

mkdir out
cat > out/memo.yml <<'EOF'
task: fix csv export
created: 2026-11-13 10:00
status: open
cwd: /work/myapp
branch: fix/csv-export
head: 1a2b3c4
goal: Fix the CSV export that drops the last row
done:
  - Pinned the csv gem to 3.2.0 in Gemfile.lock
in_progress:
  - Writing the failing test for the 10-row case
next:
  - Ask the customer for the 2 GB file
  - Fix the batch loop at app/exports/csv.rb:42
EOF
