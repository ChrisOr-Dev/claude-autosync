#!/usr/bin/env python3
"""Manage in-project memory config in a project's .claude/settings.local.json.

  set-project-memory.py <settings> <mem_dir> <project>   # enable in-project mode
  set-project-memory.py --unset <settings>               # revert to central mode

Idempotent, preserves unrelated keys."""
import json
import os
import sys

MARKER = "git add claude-memory"  # identifies the Stop hook this tool added


def load(settings_path):
    if not os.path.exists(settings_path):
        return {}
    try:
        with open(settings_path, encoding="utf-8") as f:
            return json.load(f) or {}
    except (json.JSONDecodeError, OSError):
        print(f"[!] Could not parse {settings_path}; leaving it untouched.", file=sys.stderr)
        sys.exit(1)


def save(settings_path, settings):
    with open(settings_path, "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
        f.write("\n")


def drop_memory_stop_hooks(settings):
    stops = settings.get("hooks", {}).get("Stop", [])
    kept = [
        e for e in stops
        if not any(MARKER in h.get("command", "") for h in e.get("hooks", []))
    ]
    if "hooks" in settings:
        if kept:
            settings["hooks"]["Stop"] = kept
        else:
            settings["hooks"].pop("Stop", None)


def main():
    if sys.argv[1] == "--unset":
        settings_path = sys.argv[2]
        if not os.path.exists(settings_path):
            return
        settings = load(settings_path)
        settings.pop("autoMemoryDirectory", None)
        drop_memory_stop_hooks(settings)
        save(settings_path, settings)
        return

    settings_path, mem_dir, project = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(os.path.dirname(settings_path), exist_ok=True)
    settings = load(settings_path)

    settings["autoMemoryDirectory"] = mem_dir
    stop_cmd = (
        f'cd "{project}" && git add claude-memory/ && '
        f'git diff --cached --quiet || '
        f'git commit -m "chore: update claude memory" 2>/dev/null || true'
    )
    hooks = settings.setdefault("hooks", {})
    stops = hooks.setdefault("Stop", [])
    already = any(
        MARKER in h.get("command", "")
        for entry in stops
        for h in entry.get("hooks", [])
    )
    if not already:
        stops.append({"matcher": "", "hooks": [{"type": "command", "command": stop_cmd}]})

    save(settings_path, settings)


if __name__ == "__main__":
    main()
