#!/usr/bin/env bash
# super-board-issue-sync.sh — make the board watch the repo's own issues (fork).
#
# super-board only adds issues it files itself. This adds the repo's open
# issues to the Project board so every task is visible there:
#   - an issue not on the board yet      → added to Backlog
#   - ... that carries the ready label   → added to Ready instead
#   - an issue already on the board      → left exactly where it is
#   - an issue assigned to anyone other than the bot identity is skipped
#     (that person owns it), unless --include-assigned
#   - an issue labelled no-agent is always skipped
#
# Usage:
#   super-board-issue-sync.sh [--config <path>] [--ready-label <l>] [--skip-label <l>]...
#                             [--issue <N>] [--include-assigned] [--dry-run]
# Defaults: config = the active pointer, ready label = agent-ready,
#           skip labels = no-agent.
# Exit: 0 ok · 64 bad args/config · 70 gh failure.
set -euo pipefail

CONFIG=""
READY_LABEL="agent-ready"
SKIP_LABELS=("no-agent")
ONE_ISSUE=""
INCLUDE_ASSIGNED=0
DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    --ready-label) READY_LABEL="$2"; shift 2 ;;
    --skip-label) SKIP_LABELS+=("$2"); shift 2 ;;
    --issue) ONE_ISSUE="$2"; shift 2 ;;
    --include-assigned) INCLUDE_ASSIGNED=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

if [ -z "$CONFIG" ]; then
  ptr=".claude/super-board/active"
  [ -f "$ptr" ] && CONFIG=".claude/super-board/configs/$(tr -d '[:space:]' < "$ptr").json"
fi
[ -n "$CONFIG" ] && [ -f "$CONFIG" ] || { echo "no config (pass --config)" >&2; exit 64; }

OWNER=$(jq -r '.project.owner // empty' "$CONFIG")
NUMBER=$(jq -r '.project.number // empty' "$CONFIG")
REMOTE=$(jq -r '.repo.remote // empty' "$CONFIG")
BOT=$(jq -r '.notifications.bot_identity // "auto"' "$CONFIG")
[ "$BOT" = "auto" ] && BOT=$(gh api user --jq .login 2>/dev/null || echo "")
[ -n "$OWNER" ] && [ -n "$NUMBER" ] && [ -n "$REMOTE" ] || { echo "config needs project.owner, project.number, repo.remote" >&2; exit 64; }
REPO=$(echo "$REMOTE" | sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git$##')

# Rate-limit discipline when the guard is installed.
GUARD=".claude/bin/super-board-gh-guard.sh"
# shellcheck disable=SC1090
if [ -f "$GUARD" ]; then . "$GUARD"; sb_gh_guard_check 100 || exit 70; fi

# Issues already on the board, by URL.
on_board=$(gh project item-list "$NUMBER" --owner "$OWNER" --limit 2000 --format json \
  --jq '[.items[] | select(.content.type=="Issue") | .content.url] | .[]') || exit 70

project_id=$(gh project view "$NUMBER" --owner "$OWNER" --format json --jq '.id') || exit 70
fields=$(gh project field-list "$NUMBER" --owner "$OWNER" --format json) || exit 70
field_id=$(echo "$fields" | jq -r '.fields[] | select(.name=="Status") | .id')
opt() { echo "$fields" | jq -r --arg c "$1" '.fields[] | select(.name=="Status") | .options[]? | select(.name==$c) | .id'; }
backlog_id=$(opt Backlog); ready_id=$(opt Ready)
[ -n "$field_id" ] && [ -n "$backlog_id" ] && [ -n "$ready_id" ] || { echo "board needs a Status field with Backlog and Ready" >&2; exit 64; }

if [ -n "$ONE_ISSUE" ]; then
  issues=$(gh issue view "$ONE_ISSUE" --repo "$REPO" --json number,url,labels,assignees,state \
    --jq '[.] | map(select(.state=="OPEN"))') || exit 70
else
  issues=$(gh issue list --repo "$REPO" --state open --limit 1000 \
    --json number,url,labels,assignees) || exit 70
fi

added=0; skipped=0; present=0
while IFS= read -r row; do
  [ -n "$row" ] || continue
  n=$(echo "$row" | jq -r '.number'); url=$(echo "$row" | jq -r '.url')
  labels=$(echo "$row" | jq -r '[.labels[].name] | join(",")')
  if grep -qxF "$url" <<<"$on_board"; then present=$((present+1)); continue; fi
  skip=0
  for s in "${SKIP_LABELS[@]}"; do [[ ",$labels," == *",$s,"* ]] && skip=1; done
  if [ "$INCLUDE_ASSIGNED" -eq 0 ]; then
    humans=$(echo "$row" | jq -r --arg bot "$BOT" '[.assignees[].login | select(. != $bot)] | length')
    [ "$humans" -gt 0 ] && skip=1
  fi
  if [ "$skip" -eq 1 ]; then skipped=$((skipped+1)); continue; fi
  if [[ ",$labels," == *",$READY_LABEL,"* ]]; then col=Ready; cid=$ready_id; else col=Backlog; cid=$backlog_id; fi
  if [ "$DRY" -eq 1 ]; then echo "would add #$n → $col"; added=$((added+1)); continue; fi
  item=$(gh project item-add "$NUMBER" --owner "$OWNER" --url "$url" --format json --jq '.id') || exit 70
  gh project item-edit --id "$item" --project-id "$project_id" --field-id "$field_id" \
    --single-select-option-id "$cid" >/dev/null || exit 70
  echo "added #$n → $col"
  added=$((added+1))
done < <(echo "$issues" | jq -c '.[]')

echo "issue-sync: added=$added already_on_board=$present skipped=$skipped (repo $REPO → project $OWNER/$NUMBER)"
