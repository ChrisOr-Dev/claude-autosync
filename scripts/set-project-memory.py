#!/usr/bin/env python3
"""Set autoMemoryDirectory + a project-level Stop hook (auto-commit claude-memory/)
in a project's .claude/settings.local.json. Idempotent, preserves existing keys."""
import json
import os
import sys


def main():
    settings_path, mem_dir, project = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(os.path.dirname(settings_path), exist_ok=True)

    settings = {}
    if os.path.exists(settings_path):
        try:
            with open(settings_path, encoding="utf-8") as f:
                settings = json.load(f) or {}
        except (json.JSONDecodeError, OSError):
            print(f"[!] Could not parse {settings_path}; leaving it untouched.", file=sys.stderr)
            sys.exit(1)

    settings["autoMemoryDirectory"] = mem_dir

    marker = f"cd {project} && git add claude-memory"
    stop_cmd = (
        f'cd {project} && git add claude-memory/ && '
        f'git diff --cached --quiet || '
        f'git commit -m "chore: update claude memory" 2>/dev/null || true'
    )
    hooks = settings.setdefault("hooks", {})
    stops = hooks.setdefault("Stop", [])
    already = any(
        marker in h.get("command", "")
        for entry in stops
        for h in entry.get("hooks", [])
    )
    if not already:
        stops.append({"hooks": [{"type": "command", "command": stop_cmd}]})

    with open(settings_path, "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
        f.write("\n")


if __name__ == "__main__":
    main()
