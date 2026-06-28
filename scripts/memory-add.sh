#!/usr/bin/env bash
# memory-add.sh — add ONE project's memory to claude-autosync.
#
# Two modes:
#   central     (default, SAFE) — memory lives in YOUR central private repo at
#               ~/.claude-autosync/memory/<name>/, symlinked in. Never touches the
#               project repo, so it is safe even for PUBLIC projects.
#   in-project  (opt-in)        — memory lives in <project>/claude-memory/ and
#               travels with the project's own git (via autoMemoryDirectory).
#               Refused on PUBLIC repos to prevent leaking personal notes.
#
# Usage:
#   memory-add.sh <project-path> [--mode central|in-project] [--name <alias>] [--force-in-project]
#
#   --name <alias>        central only: use memory/<alias>/ instead of the path slug,
#                         so the SAME project on machines with different paths shares
#                         one folder. Defaults to the path slug.
#   --force-in-project    allow in-project when repo visibility can't be verified
#                         (no gh / no remote). Never overrides a confirmed PUBLIC repo.
set -euo pipefail

SYNC_DIR="$HOME/.claude-autosync"
CLAUDE_DIR="$HOME/.claude"
TPL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d%H%M%S)"

PROJECT=""
MODE="central"
NAME=""
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)              MODE="${2:-}"; shift 2 ;;
    --name)              NAME="${2:-}"; shift 2 ;;
    --force-in-project)  FORCE=1; shift ;;
    -h|--help)
      sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *)  PROJECT="$1"; shift ;;
  esac
done

if [ -z "$PROJECT" ]; then
  echo "usage: memory-add.sh <project-path> [--mode central|in-project] [--name <alias>] [--force-in-project]" >&2
  exit 1
fi
case "$MODE" in central|in-project) ;; *) echo "Invalid --mode: $MODE (central|in-project)" >&2; exit 1 ;; esac

PROJECT="$(cd "$PROJECT" && pwd)"
SLUG="$(printf '%s' "$PROJECT" | sed 's:/:-:g')"
MEM_DEST="$CLAUDE_DIR/projects/$SLUG/memory"
mkdir -p "$SYNC_DIR/memory" "$(dirname "$MEM_DEST")"

# ── in-project: verify the repo is PRIVATE before writing memory into it ──────
if [ "$MODE" = "in-project" ]; then
  if ! git -C "$PROJECT" rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: $PROJECT is not a git repo; in-project mode needs one." >&2
    exit 1
  fi
  VIS="unknown"
  if command -v gh >/dev/null 2>&1; then
    # '|| true' keeps a gh failure (e.g. no remote) from tripping set -e/pipefail
    _v="$( (cd "$PROJECT" && gh repo view --json visibility -q '.visibility' 2>/dev/null) \
            | tr '[:upper:]' '[:lower:]' || true )"
    [ -n "$_v" ] && VIS="$_v"
  fi
  if [ "$VIS" = "public" ]; then
    echo "[BLOCKED] $PROJECT is a PUBLIC repo — refusing in-project memory (would leak"
    echo "          personal notes). Falling back to central mode."
    MODE="central"
  elif [ "$VIS" = "unknown" ] && [ "$FORCE" -ne 1 ]; then
    echo "[BLOCKED] Cannot verify repo visibility (no gh, or no remote set)." >&2
    echo "          Re-run with --force-in-project only if you are SURE it is private." >&2
    exit 1
  fi
fi

# ── central mode ─────────────────────────────────────────────────────────────
if [ "$MODE" = "central" ]; then
  NAME="${NAME:-$SLUG}"
  REPO_MEM="$SYNC_DIR/memory/$NAME"
  if [ ! -d "$REPO_MEM" ]; then
    mkdir -p "$REPO_MEM"
    cp "$TPL_DIR/templates/memory/MEMORY.md" "$REPO_MEM/MEMORY.md"
  fi
  # migrate any existing real memory (non-destructive), then symlink
  if [ -d "$MEM_DEST" ] && [ ! -L "$MEM_DEST" ]; then
    cp -n "$MEM_DEST"/*.md "$REPO_MEM/" 2>/dev/null || true
    mv "$MEM_DEST" "$MEM_DEST.bak.$STAMP"
    echo "[*] Backed up existing memory -> ${MEM_DEST##*/}.bak.$STAMP"
  fi
  ln -sfn "$REPO_MEM" "$MEM_DEST"
  echo "[OK] central memory: $MEM_DEST -> $REPO_MEM"
  echo "     (name: $NAME — reuse the same --name on other machines to share it)"
  exit 0
fi

# ── in-project mode (verified private / forced) ──────────────────────────────
DEST="$PROJECT/claude-memory"
mkdir -p "$DEST"
[ -f "$DEST/MEMORY.md" ] || cp "$TPL_DIR/templates/memory/MEMORY.md" "$DEST/MEMORY.md"

# migrate existing memory (real dir or a prior central symlink) into the project
if [ -L "$MEM_DEST" ]; then
  cp -n "$(readlink "$MEM_DEST")"/*.md "$DEST/" 2>/dev/null || true
  rm "$MEM_DEST"
elif [ -d "$MEM_DEST" ]; then
  cp -n "$MEM_DEST"/*.md "$DEST/" 2>/dev/null || true
  mv "$MEM_DEST" "$MEM_DEST.bak.$STAMP"
fi

python3 "$TPL_DIR/scripts/set-project-memory.py" "$PROJECT/.claude/settings.local.json" "$DEST" "$PROJECT"

if git -C "$PROJECT" check-ignore -q claude-memory 2>/dev/null; then
  echo "[!] claude-memory/ is gitignored in this project — add '!claude-memory/' to track it."
fi
git -C "$PROJECT" add claude-memory/ .claude/settings.local.json 2>/dev/null || true

echo "[OK] in-project memory: autoMemoryDirectory -> $DEST"
echo "     A project Stop hook will auto-commit claude-memory/. Push it yourself:"
echo "       git -C \"$PROJECT\" commit -m \"chore: add claude-memory/\" && git -C \"$PROJECT\" push"
