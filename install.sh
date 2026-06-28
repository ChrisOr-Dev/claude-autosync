#!/usr/bin/env bash
# claude-autosync — installer (macOS / Linux / WSL)
#
# Wires your machine to sync Claude Code's global rules (CLAUDE.md) and
# memory to YOUR OWN private git repo. This tool stores no data itself.
#
# Usage:
#   ./install.sh <your-private-repo-url> [memory-project-path]
#
# Example:
#   ./install.sh git@github.com:yourname/my-claude-config.git ~/Projects
#
# Create an EMPTY PRIVATE repo on your own GitHub first.
set -euo pipefail

REPO_URL="${1:-}"
MEMORY_PROJECT="${2:-$HOME}"
SYNC_DIR="$HOME/.claude-autosync"
CLAUDE_DIR="$HOME/.claude"
TPL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d%H%M%S)"

if [ -z "$REPO_URL" ]; then
  echo "Usage: ./install.sh <your-private-repo-url> [memory-project-path]"
  echo "Create an EMPTY PRIVATE repo on your own GitHub first."
  exit 1
fi

echo "=== claude-autosync install ==="
echo "  private repo : $REPO_URL"
echo "  sync dir     : $SYNC_DIR"
echo "  memory for   : $MEMORY_PROJECT"

# 1. Clone (or init) the private config repo at a fixed, OS-stable location
if [ -d "$SYNC_DIR/.git" ]; then
  echo "[*] Updating existing sync dir..."
  git -C "$SYNC_DIR" pull --quiet || true
else
  echo "[*] Cloning private repo..."
  if ! git clone "$REPO_URL" "$SYNC_DIR" 2>/dev/null; then
    echo "[*] Repo empty or unreachable for clone; initializing locally..."
    mkdir -p "$SYNC_DIR"
    git -C "$SYNC_DIR" init -q
    git -C "$SYNC_DIR" remote add origin "$REPO_URL"
  fi
fi

# 2. First-run scaffold from templates (only if files don't exist yet)
if [ ! -f "$SYNC_DIR/CLAUDE.md" ]; then
  echo "[*] Scaffolding CLAUDE.md + memory from templates..."
  cp "$TPL_DIR/templates/CLAUDE.md" "$SYNC_DIR/CLAUDE.md"
  mkdir -p "$SYNC_DIR/memory"
  cp "$TPL_DIR/templates/memory/MEMORY.md" "$SYNC_DIR/memory/MEMORY.md"
  cp "$TPL_DIR/templates/private-gitignore" "$SYNC_DIR/.gitignore"
fi
cp "$TPL_DIR/scripts/sync.sh" "$SYNC_DIR/sync.sh"
chmod +x "$SYNC_DIR/sync.sh"
mkdir -p "$CLAUDE_DIR" "$SYNC_DIR/memory"

# 3. Per-machine local.md — gitignored, NEVER synced (paths, hosts, secrets)
if [ ! -f "$SYNC_DIR/local.md" ]; then
  cp "$TPL_DIR/templates/local.md.example" "$SYNC_DIR/local.md" 2>/dev/null || touch "$SYNC_DIR/local.md"
  echo "[*] Created $SYNC_DIR/local.md (edit this for machine-specific config)"
fi

# 4. Symlink global CLAUDE.md (back up any existing real file first)
if [ -e "$CLAUDE_DIR/CLAUDE.md" ] && [ ! -L "$CLAUDE_DIR/CLAUDE.md" ]; then
  mv "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md.bak.$STAMP"
  echo "[*] Backed up existing CLAUDE.md -> CLAUDE.md.bak.$STAMP"
fi
ln -sf "$SYNC_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
echo "[OK] CLAUDE.md -> $SYNC_DIR/CLAUDE.md"

# 5. Symlink the memory dir for the chosen project
#    Claude Code derives the slug by replacing '/' with '-' in the project path.
SLUG="$(printf '%s' "$MEMORY_PROJECT" | sed 's:/:-:g')"
MEM_DEST="$CLAUDE_DIR/projects/$SLUG/memory"
mkdir -p "$(dirname "$MEM_DEST")"
if [ -e "$MEM_DEST" ] && [ ! -L "$MEM_DEST" ]; then
  echo "[*] Merging existing memory into repo (non-destructive)..."
  cp -n "$MEM_DEST"/*.md "$SYNC_DIR/memory/" 2>/dev/null || true
  mv "$MEM_DEST" "$MEM_DEST.bak.$STAMP"
  echo "[*] Backed up existing memory -> ${MEM_DEST##*/}.bak.$STAMP"
fi
ln -sfn "$SYNC_DIR/memory" "$MEM_DEST"
echo "[OK] memory -> $SYNC_DIR/memory  (slug: $SLUG)"

# 6. Wire SessionStart (pull) + Stop (push) hooks into settings.json
if command -v python3 >/dev/null 2>&1; then
  python3 "$TPL_DIR/scripts/wire-hooks.py" "$CLAUDE_DIR/settings.json" "$SYNC_DIR/sync.sh" \
    && echo "[OK] Hooks wired into $CLAUDE_DIR/settings.json"
else
  echo ""
  echo "[!] python3 not found — add these hooks to $CLAUDE_DIR/settings.json manually:"
  echo "    SessionStart -> $SYNC_DIR/sync.sh pull"
  echo "    Stop         -> $SYNC_DIR/sync.sh push"
fi

# 7. Initial push so the private repo has your config
"$SYNC_DIR/sync.sh" push || true

echo ""
echo "=== Done ==="
echo "Edit machine-specific config: $SYNC_DIR/local.md"
echo "Shared rules:                 $SYNC_DIR/CLAUDE.md"
echo "Run on another machine:       ./install.sh $REPO_URL <that-machine-project-path>"
