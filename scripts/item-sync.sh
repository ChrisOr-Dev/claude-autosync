#!/usr/bin/env bash
# item-sync.sh — choose which Claude Code skills / commands sync to YOUR private repo.
#
# Selection is OPT-IN: nothing syncs until you promote it. A promoted item is
# MOVED into ~/.claude-autosync/{skills,commands}/ and symlinked back, so it is
# the single source of truth and rides the normal pull/push hooks. Local items
# you never promote stay on this machine only (safe for machine-specific or
# private skills).
#
# Usage:
#   item-sync.sh skill                      # TTY: interactive checklist of all skills
#   item-sync.sh skill <name> [<name>...]   # promote one or more by name
#   item-sync.sh skill --list               # show synced vs local-only
#   item-sync.sh skill --unset <name>       # stop syncing; KEEP a local copy everywhere
#   item-sync.sh skill --purge <name>       # remove everywhere (use for mistakes / secrets)
#   item-sync.sh command ...                # same, for slash commands (~/.claude/commands/*.md)
#
# --unset is non-destructive: this machine keeps a real local copy, and every
# other machine recovers its own local copy on the next pull. --purge deletes it
# on all machines (git history in your private repo still retains it).
set -uo pipefail

SYNC_DIR="$HOME/.claude-autosync"
CLAUDE_DIR="$HOME/.claude"
STAMP="$(date +%Y%m%d%H%M%S)"

TYPE="${1:-}"; shift 2>/dev/null || true
case "$TYPE" in
  skill)   SUB="skills";   SUFFIX="";    IS_DIR=1 ;;
  command) SUB="commands"; SUFFIX=".md"; IS_DIR=0 ;;
  -h|--help|"")
    sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  *) echo "first arg must be 'skill' or 'command' (got: $TYPE)" >&2; exit 1 ;;
esac

REPO_SUB="$SYNC_DIR/$SUB"
CLAUDE_SUB="$CLAUDE_DIR/$SUB"

repo_item()   { echo "$REPO_SUB/$1$SUFFIX"; }
claude_item() { echo "$CLAUDE_SUB/$1$SUFFIX"; }

# names currently synced (present in the private repo)
list_synced() {
  [ -d "$REPO_SUB" ] || return 0
  local e n
  for e in "$REPO_SUB"/*; do
    [ -e "$e" ] || continue
    n="$(basename "$e")"; echo "${n%$SUFFIX}"
  done
}

# names that exist locally but are NOT synced (real items, not our symlinks)
list_local_only() {
  [ -d "$CLAUDE_SUB" ] || return 0
  local e n
  for e in "$CLAUDE_SUB"/*; do
    [ -e "$e" ] || continue
    if [ "$IS_DIR" = 1 ]; then [ -d "$e" ] || continue
    else case "$e" in *.md) ;; *) continue ;; esac; fi
    [ -L "$e" ] && continue
    n="$(basename "$e")"; echo "${n%$SUFFIX}"
  done
}

in_list() { printf '%s\n' "$1" | grep -Fqx "$2"; }

# ── promote: move a local item into the repo and symlink it back ──────────────
promote() {
  local name="$1" src dest
  src="$(claude_item "$name")"
  dest="$(repo_item "$name")"

  if [ -L "$src" ] && [ "$(readlink "$src")" = "$dest" ]; then
    echo "[=] $TYPE '$name' already synced"; return 0
  fi
  if [ ! -e "$src" ] && [ ! -e "$dest" ]; then
    echo "[!] no such $TYPE: '$name' (looked in $CLAUDE_SUB)" >&2; return 1
  fi

  mkdir -p "$REPO_SUB"
  if [ -e "$dest" ]; then
    # already in the repo (synced from another machine): reconcile this machine
    if [ -e "$src" ] && [ ! -L "$src" ]; then
      if diff -rq "$src" "$dest" >/dev/null 2>&1; then rm -rf "$src"
      else mv "$src" "$src.local.bak.$STAMP"; echo "[*] local '$name' differs — backed up to $name.local.bak.$STAMP"; fi
    else
      rm -f "$src" 2>/dev/null || true
    fi
  else
    mv "$src" "$dest"
  fi
  ln -sfn "$dest" "$src"
  echo "[OK] sync $TYPE '$name'  ($src -> $dest)"
}

# ── unset: stop syncing but keep a real local copy (non-destructive) ──────────
unset_item() {
  local name="$1" src dest
  src="$(claude_item "$name")"
  dest="$(repo_item "$name")"
  if [ ! -e "$dest" ]; then echo "[!] $TYPE '$name' is not synced" >&2; return 1; fi
  rm -f "$src" 2>/dev/null || true        # drop the symlink
  cp -RL "$dest" "$src"                    # keep a local copy on THIS machine
  git -C "$SYNC_DIR" rm -r --quiet "$SUB/$name$SUFFIX" 2>/dev/null || true
  echo "[OK] unsynced $TYPE '$name' — kept local copy here; other machines keep theirs on next pull"
}

# ── purge: remove everywhere (this commit is tagged so pulls delete, not keep) ─
purge_item() {
  local name="$1" src dest
  src="$(claude_item "$name")"
  dest="$(repo_item "$name")"
  if [ ! -e "$dest" ]; then echo "[!] $TYPE '$name' is not synced" >&2; return 1; fi
  rm -rf "$src" 2>/dev/null || true
  git -C "$SYNC_DIR" rm -r --quiet "$SUB/$name$SUFFIX" 2>/dev/null || true
  git -C "$SYNC_DIR" commit -q -m "purge: $TYPE $name" 2>/dev/null || true
  echo "[OK] purged $TYPE '$name' — removed everywhere on next pull (git history still retains it)"
}

show_list() {
  local synced local_only
  synced="$(list_synced)"; local_only="$(list_local_only)"
  echo "synced (${SUB}):"
  if [ -n "$synced" ]; then printf '  [x] %s\n' $synced; else echo "  (none)"; fi
  echo "local-only:"
  if [ -n "$local_only" ]; then printf '  [ ] %s\n' $local_only; else echo "  (none)"; fi
}

# ── interactive checklist (no names given on a TTY) ───────────────────────────
# Builds desired state, then promotes newly-checked / unsets newly-unchecked.
apply_desired() {
  local desired="$1" synced name
  synced="$(list_synced)"
  for name in $(list_local_only); do
    in_list "$desired" "$name" && promote "$name"
  done
  for name in $synced; do
    in_list "$desired" "$name" || unset_item "$name"
  done
}

checklist() {
  local synced local_only all desired=""
  synced="$(list_synced)"; local_only="$(list_local_only)"
  all="$(printf '%s\n%s\n' "$synced" "$local_only" | grep -v '^$' | sort -u)"
  if [ -z "$all" ]; then echo "no $SUB found under $CLAUDE_SUB"; return 0; fi

  if command -v whiptail >/dev/null 2>&1; then
    local args=() name st
    while IFS= read -r name; do
      in_list "$synced" "$name" && st=ON || st=OFF
      args+=("$name" "" "$st")
    done <<< "$all"
    desired="$(whiptail --title "claude-autosync: sync $SUB" \
      --checklist "Space toggles. Checked = synced to your private repo." \
      20 70 12 "${args[@]}" 3>&1 1>&2 2>&3)" || { echo "cancelled"; return 0; }
    desired="$(printf '%s\n' $desired | tr -d '"')"
  else
    # zero-dependency numbered toggle
    local -a names=(); local i=1 name marks
    echo "Select $SUB to sync (checked = synced):"
    while IFS= read -r name; do
      names+=("$name")
      in_list "$synced" "$name" && marks="[x]" || marks="[ ]"
      printf '  %2d) %s %s\n' "$i" "$marks" "$name"; i=$((i+1))
    done <<< "$all"
    printf 'Enter numbers to TOGGLE (space-separated), empty = no change: '
    read -r toggles
    # start from current synced set, flip toggled indices
    local n cur="$synced"
    for n in $toggles; do
      case "$n" in *[!0-9]*|"") continue ;; esac
      [ "$n" -ge 1 ] && [ "$n" -le "${#names[@]}" ] || continue
      name="${names[$((n-1))]}"
      if in_list "$cur" "$name"; then cur="$(printf '%s\n' $cur | grep -Fvx "$name")"
      else cur="$(printf '%s\n%s\n' "$cur" "$name")"; fi
    done
    desired="$cur"
  fi
  apply_desired "$desired"
}

# ── dispatch ──────────────────────────────────────────────────────────────────
MUTATED=0
if [ $# -eq 0 ]; then
  if [ -t 0 ]; then checklist && MUTATED=1; else show_list; fi
else
  case "$1" in
    --list|-l) show_list ;;
    --unset)   shift; for n in "$@"; do unset_item "$n"; done; MUTATED=1 ;;
    --purge)   shift; for n in "$@"; do purge_item "$n"; done; MUTATED=1 ;;
    -*) echo "unknown option: $1" >&2; exit 1 ;;
    *)  for n in "$@"; do promote "$n"; done; MUTATED=1 ;;
  esac
fi

# propagate immediately so other machines get it on their next pull
if [ "$MUTATED" -eq 1 ] && [ -x "$SYNC_DIR/sync.sh" ]; then
  "$SYNC_DIR/sync.sh" push >/dev/null 2>&1 || true
  echo "[*] pushed to your private repo"
fi
exit 0
