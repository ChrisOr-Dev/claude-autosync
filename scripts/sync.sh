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

case "$MODE" in
  pull)
    git pull --quiet --no-rebase 2>/dev/null || true
    ;;
  push)
    git add -A 2>/dev/null || true
    if ! git diff --cached --quiet 2>/dev/null; then
      HOST="$(hostname 2>/dev/null || echo unknown)"
      git commit -q -m "sync: ${HOST} $(date +%Y-%m-%dT%H:%M:%S)" 2>/dev/null || true
      git push --quiet 2>/dev/null || true
    fi
    ;;
  *)
    echo "usage: sync.sh pull|push" >&2
    exit 1
    ;;
esac
exit 0
