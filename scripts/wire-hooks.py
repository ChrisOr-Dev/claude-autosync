#!/usr/bin/env python3
"""Merge claude-autosync hooks into ~/.claude/settings.json without clobbering
existing config. Idempotent: re-running won't add duplicates."""
import json
import os
import sys


def load(path):
    if not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f) or {}
    except (json.JSONDecodeError, OSError):
        print(f"[!] Could not parse {path}; leaving it untouched.", file=sys.stderr)
        sys.exit(1)


def ensure_hook(settings, event, command):
    hooks = settings.setdefault("hooks", {})
    entries = hooks.setdefault(event, [])
    # Already present? (search nested hook command strings)
    for entry in entries:
        for h in entry.get("hooks", []):
            if h.get("command") == command:
                return False
    entries.append({"hooks": [{"type": "command", "command": command}]})
    return True


def main():
    settings_path = sys.argv[1]
    sync_sh = sys.argv[2]
    settings = load(settings_path)

    changed = False
    changed |= ensure_hook(settings, "SessionStart", f"{sync_sh} pull")
    changed |= ensure_hook(settings, "Stop", f"{sync_sh} push")

    if changed:
        if os.path.exists(settings_path):
            os.replace(settings_path, settings_path + ".bak")
        with open(settings_path, "w", encoding="utf-8") as f:
            json.dump(settings, f, indent=2)
            f.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
