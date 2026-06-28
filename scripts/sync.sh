#!/usr/bin/env bash
# claude-autosync — sync driver. Invoked by Claude Code hooks.
#   sync.sh pull   -> pull latest config from your private repo (SessionStart)
#   sync.sh push   -> commit + push local changes (Stop)
# Silent and non-fatal by design: never block a Claude session.
set -uo pipefail

SYNC_DIR="$HOME/.claude-autosync"
MODE="${1:-pull}"
cd "$SYNC_DIR" 2>/dev/null || exit 0
[ -d "$SYNC_DIR/.git" ] || exit 0

BR="$(git symbolic-ref --short HEAD 2>/dev/null || echo main)"

case "$MODE" in
  pull)
    # try tracked pull, then fall back to explicit remote/branch (no upstream yet)
    git pull --quiet --no-rebase 2>/dev/null \
      || git pull --quiet --no-rebase origin "$BR" 2>/dev/null || true
    # if the merge left conflicts, abort rather than commit conflict markers
    GD="$(git rev-parse --git-dir 2>/dev/null || echo .git)"
    if [ -f "$GD/MERGE_HEAD" ] && git ls-files -u 2>/dev/null | grep -q .; then
      git merge --abort 2>/dev/null || true
      echo "claude-autosync: pull conflict aborted — resolve manually in $SYNC_DIR" >&2
    fi
    ;;
  push)
    git add -A 2>/dev/null || true
    if ! git diff --cached --quiet 2>/dev/null; then
      HOST="$(hostname 2>/dev/null || echo unknown)"
      git commit -q -m "sync: ${HOST} $(date +%Y-%m-%dT%H:%M:%S)" 2>/dev/null || true
    fi
    # push; on first push (no upstream) retry with -u to set tracking
    git push --quiet 2>/dev/null \
      || git push -u origin "$BR" --quiet 2>/dev/null || true
    ;;
  *)
    echo "usage: sync.sh pull|push" >&2
    exit 1
    ;;
esac
exit 0
