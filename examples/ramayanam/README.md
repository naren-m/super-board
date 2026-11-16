# Ramayanam pack (quick version)

A team of specialist agents run by super-board. Each GitHub issue gets a
label, the board sends it to the matching specialist, and the Project board
shows every task.

```
your issue ──label──▶ board (Backlog → Ready → Building → QA → Review → Done)
                         │
                         ├─ area:guru    → agents/guru.md      (Guru Q&A pipeline)
                         ├─ area:corpus  → agents/corpus.md    (data, KG, commentary, stories)
                         ├─ area:ui      → agents/ui.md        (React UI)
                         ├─ design       → agents/architect.md (design doc + child issues)
                         └─ no label     → generic builder
eval-grader.md: you run it after deploys; it is not on the board.
```

## What the fork adds
| Piece | File |
|---|---|
| Label → specialist routing in every lane prompt | `workflows/super-board-wave.js` (`specialistOf`) |
| The board watches the repo's open issues | `scripts/super-board-issue-sync.sh` |
| Per-project deny list (held-out set, Ollama endpoint) | `hooks/guard-project-deny.py` + `deny.json` |

## Set up (once, in the Ramayanam repo)
1. Install from the fork, pinned to this branch:
   ```bash
   cd ~/Projects/ramayanam
   curl -fsSL https://raw.githubusercontent.com/naren-m/super-board/feature/specialist-agents/get.sh \
     | SUPER_BOARD_REPO=naren-m/super-board bash -s -- --ref feature/specialist-agents --no-helper-skills --protect-main
   ```
2. Copy the pack in:
   ```bash
   P=<path-to-super-board-clone>/examples/ramayanam
   mkdir -p .claude/agents .claude/super-board
   cp $P/agents/*.md .claude/agents/
   cp $P/deny.json .claude/super-board/deny.json
   ```
3. `/super-board onboard`, then merge `config-overrides.json` into the config it writes
   (`.claude/super-board/configs/<slug>.json`): every merge waits for you, and the
   checks are your `make` targets.
4. Create the labels: `area:guru`, `area:corpus`, `area:ui`, `design`, `agent-ready`, `no-agent`.
5. Pull your issues onto the board, then run it:
   ```bash
   .claude/bin/super-board-issue-sync.sh --dry-run   # check first
   .claude/bin/super-board-issue-sync.sh
   ```
   `/super-board run`

## Day to day
- New task: open an issue, add one `area:` label (or `design` for a big one).
  Add `agent-ready` to send it straight to Ready; otherwise it waits in Backlog.
- Re-run `super-board-issue-sync.sh` before a run to pick up new issues.
- Merges stop for you (`merge_policy.default: human`), because a merge to `main` deploys
  to ramayanam.naren.me within ~10 minutes.
- After a deploy, run the eval grader yourself: `SUPER_BOARD_DENY_BYPASS=1 claude`, then
  "act as .claude/agents/eval-grader.md".

## Known gaps (quick version)
- Routing uses the workflow backend only; the legacy `claude-p` runner ignores the labels.
- Issue sync is manual (run the script); it is not yet called at the start of each wave.
- No eval column: Guru changes are judged by the eval grader after merge, by hand.
- Lanes (lanes.sh) as a live view is not wired in yet.
