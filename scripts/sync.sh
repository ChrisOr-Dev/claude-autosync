#!/usr/bin/env bash
# claude-autosync sync driver. Invoked by Claude Code hooks.
#
#   sync.sh pull             pull latest config (SessionStart). Prints a receipt.
#   sync.sh push             commit + push local changes (Stop). Prints a receipt.
#   sync.sh status [--json]  READ-ONLY: report sync state without changing anything.
#   pull/push accept --dry-run to print state without mutating.
#
# Fail-open (never blocks a Claude session) but NOT fail-silent: every run prints
# a one-line receipt to stderr, and conflicts / push rejects are reported, not
# swallowed. A mkdir lock serializes concurrent sessions; push retries on a
# non-fast-forward reject by integrating the remote first (no lost updates).
set -uo pipefail

# Never let git block a Claude session waiting on a credential prompt.
export GIT_TERMINAL_PROMPT=0
: "${GIT_SSH_COMMAND:=ssh -oBatchMode=yes}"; export GIT_SSH_COMMAND

AUTOSYNC_VERSION="0.2.0"
DIR="$HOME/.claude-autosync"
SUBCMD="${1:-pull}"; shift 2>/dev/null || true
JSON=0; DRY=0
for a in "$@"; do case "$a" in --json) JSON=1 ;; --dry-run) DRY=1 ;; esac; done

cd "$DIR" 2>/dev/null || exit 0
[ -d .git ] || exit 0
BR="$(git symbolic-ref --short HEAD 2>/dev/null || echo main)"
LOCK_DIR="$DIR/.sync.lock"

log() { echo "claude-autosync: $*" >&2; }

acquire_lock() {
  local i=0
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    # steal a stale lock (>2 min old — a crashed or killed hook)
    if [ -n "$(find "$LOCK_DIR" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then
      rmdir "$LOCK_DIR" 2>/dev/null || true
      continue
    fi
    i=$((i + 1)); [ "$i" -gt 10 ] && return 1
    sleep 0.5
  done
  trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
  return 0
}

in_conflict() {
  local gd; gd="$(git rev-parse --git-dir 2>/dev/null || echo .git)"
  [ -f "$gd/MERGE_HEAD" ] && git ls-files -u 2>/dev/null | grep -q .
}

# integrate remote into the local branch; abort cleanly on conflict (rc 1)
integrate() {
  git pull --quiet --no-rebase 2>/dev/null \
    || git pull --quiet --no-rebase origin "$BR" 2>/dev/null || true
  if in_conflict; then
    git merge --abort 2>/dev/null || true
    return 1
  fi
  return 0
}

do_status() {
  git fetch --quiet origin "$BR" 2>/dev/null || true
  local head rhead ahead=0 behind=0 dirty conflict localonly last
  head="$(git rev-parse --short HEAD 2>/dev/null || echo none)"
  rhead="$(git rev-parse --short "origin/$BR" 2>/dev/null || echo none)"
  if git rev-parse "origin/$BR" >/dev/null 2>&1; then
    read -r behind ahead < <(git rev-list --left-right --count "origin/$BR...HEAD" 2>/dev/null || echo "0 0")
  fi
  [ -n "$(git status --porcelain 2>/dev/null)" ] && dirty=true || dirty=false
  in_conflict && conflict=true || conflict=false
  [ -f "$DIR/local.md" ] && localonly="local.md" || localonly=""
  last="$(git log -1 --pretty='%h %s' 2>/dev/null || echo none)"
  if [ "$JSON" -eq 1 ]; then
    last="$(printf '%s' "$last" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
    printf '{"version":"%s","dir":"%s","branch":"%s","head":"%s","remote_head":"%s","ahead":%s,"behind":%s,"dirty":%s,"in_conflict":%s,"local_only":"%s","last_commit":"%s"}\n' \
      "$AUTOSYNC_VERSION" "$DIR" "$BR" "$head" "$rhead" "${ahead:-0}" "${behind:-0}" "$dirty" "$conflict" "$localonly" "$last"
  else
    log "status: v$AUTOSYNC_VERSION branch=$BR head=$head remote=$rhead ahead=${ahead:-0} behind=${behind:-0} dirty=$dirty conflict=$conflict local-only=[$localonly]"
  fi
}

case "$SUBCMD" in
  version|--version|-v)
    echo "claude-autosync $AUTOSYNC_VERSION"
    ;;

  status)
    do_status
    ;;

  pull)
    [ "$DRY" -eq 1 ] && { do_status; exit 0; }
    acquire_lock || { log "pull skipped: another sync in progress"; exit 0; }
    PREV="$(git rev-parse --short HEAD 2>/dev/null || echo none)"
    if integrate; then
      NEW="$(git rev-parse --short HEAD 2>/dev/null || echo none)"
      if [ "$PREV" = "$NEW" ]; then
        log "pull: up to date at $NEW"
      else
        FILES="$(git diff --name-only "$PREV" "$NEW" 2>/dev/null | tr '\n' ' ')"
        log "pull: rules now at $NEW (was $PREV); changed: ${FILES:-none}"
      fi
    else
      log "pull: CONFLICT aborted — rules NOT updated; resolve manually in $DIR"
    fi
    ;;

  push)
    [ "$DRY" -eq 1 ] && { do_status; exit 0; }
    acquire_lock || { log "push skipped: another sync in progress (changes go next push)"; exit 0; }
    git add -A 2>/dev/null || true
    STAGED="$(git diff --cached --name-only 2>/dev/null | tr '\n' ' ')"
    if [ -n "$STAGED" ]; then
      HOST="$(hostname 2>/dev/null || echo unknown)"
      git commit -q -m "sync: ${HOST} $(date +%Y-%m-%dT%H:%M:%S)" 2>/dev/null || true
    fi
    # push; on a non-fast-forward reject, integrate remote and retry (no lost update)
    pushed=0; conflict_hit=0
    for attempt in 1 2 3; do
      if git push --quiet 2>/dev/null || git push -u origin "$BR" --quiet 2>/dev/null; then
        pushed=1; break
      fi
      if ! integrate; then
        log "push: CONFLICT while integrating remote — aborted; resolve manually in $DIR"
        conflict_hit=1; break
      fi
    done
    AUTH="$(git rev-parse --short HEAD 2>/dev/null || echo none)"
    OMIT="none"; { [ -f "$DIR/local.md" ] && ! printf '%s\n' $STAGED | grep -qx 'local.md'; } && OMIT="local.md"
    if [ "$pushed" -eq 1 ]; then
      log "push: ok; authoritative=$AUTH; staged=[${STAGED:-none}]; kept-local=[$OMIT]"
    elif [ "$conflict_hit" -eq 0 ]; then
      log "push: FAILED after retries; local commits at $AUTH (will retry next session)"
    fi
    ;;

  *)
    log "usage: sync.sh pull|push|status [--json] [--dry-run]"
    exit 1
    ;;
esac
exit 0
