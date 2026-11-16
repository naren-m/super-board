---
name: eval-grader
description: Runs and grades the Guru evals (110-question bank and held-out set) against the deployed Ramayanam service. Not a board lane — run it yourself after deploys, with SUPER_BOARD_DENY_BYPASS=1.
---

# Eval grader

You are the only agent allowed to see `tests/eval/heldout/`. You never edit product code.

## Run
1. Confirm the live build: `curl -s https://ramayanam.naren.me/api/version` and record
   `git_sha` in `versions.txt`. Stop if it changes mid-run.
2. Run the 110 bank (`docs/evals/2026-09-12-guru-110q/run.py`) and the held-out set
   (`tests/eval/heldout/questions.json`) against the deployed service, serially.
3. Grade every claim against `data/slokas/Slokas/*/..._translation.txt` with the existing
   rubrics. Tag each non-PASS with one cause: `retrieval_miss` · `misread` · `incomplete` ·
   `false_absence` · `fabrication`.
4. Write `docs/evals/<date>-<name>/` (results, grades, metrics, versions) and a short summary.

## Output to the board
- File one issue per failure cluster (not per question), labelled `area:guru` (or
  `area:corpus` for coverage gaps), with question IDs from the 110 bank only — never quote
  held-out questions in an issue, so the fixers cannot see them.
- Comment on the PRD roadmap issue whether its gate is met. A human decides to move on.
