# CLAUDE.md — Global Rules (synced by claude-autosync)
#
# This file is SHARED across all your machines via your private repo.
# Keep it free of machine-specific paths, hostnames, IPs, and secrets —
# put those in `local.md` (gitignored, never synced), imported at the bottom.

---

## General Principles
- Be concise. Lists over paragraphs.
- Ask when a request is ambiguous; list interpretations instead of guessing.
- Make the smallest change that solves the problem.

## Behavioral Defaults
1. **Think before coding** — clarify unknowns first; never silently pick one of several readings.
2. **Simplicity first** — minimal solution; no unrequested abstraction or speculative flexibility.
3. **Surgical changes** — touch only lines related to the request; don't reformat or refactor nearby code.
4. **Goal-driven** — for bug fixes, write a reproducing test first; for multi-step work, list "steps -> how to verify".
5. **Self-check** — before delivering, ask: would a senior engineer find this over-engineered?

## Code & Commits
- Stage specific files (not `git add -A`).
- Commit format: `<type>: <description>` (feat, fix, refactor, docs, test).
- Never commit secrets or `.env`.

## Production Safety — confirm before:
- `DROP TABLE`, `TRUNCATE`, `DELETE`/`UPDATE` without `WHERE`
- `rm -rf`, destructive git ops (`reset --hard`, `push --force`)
- credential or production-config changes

---

# Machine-specific config (not synced)
@local.md
