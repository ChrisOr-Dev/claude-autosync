# Changelog

All notable changes to claude-autosync. Versions follow [SemVer](https://semver.org/).

## 0.3.0

- **Sync skills & commands (opt-in)**: `scripts/item-sync.sh skill|command`
  promotes a chosen skill/command into your private repo and symlinks it back.
  Nothing syncs until you choose it — machine-specific/private items stay local.
  Interactive checklist on a TTY (`whiptail`/`dialog`, else a zero-dep numbered
  toggle); promote by name for headless / AI-agent use.
- **Automatic materialization**: `install.sh` and every `sync.sh pull` symlink
  whatever skills/commands are already in the repo into `~/.claude/` — new
  machines receive them with no selection step. Name collisions are backed up to
  `<name>.local.bak`, never clobbered.
- **Safe unsync lifecycle**: `--unset <name>` stops syncing but keeps a local
  copy on every machine (recovered on pull); `--purge <name>` removes it
  everywhere. Conflicting delete/modify is aborted, never committed.
- **Observability**: `status --json` now reports `synced_skills` /
  `synced_commands`; pull receipts note relinked/recovered items.
- Windows (`sync.ps1`) **receives** synced skills/commands on pull; selection is
  bash-only (run under WSL).
- README restructured so **AI-agent autonomous setup is the first section**.

## 0.2.0

- **Concurrency-safe sync**: a `mkdir` lock serializes parallel sessions (with
  stale-lock reclaim), and `push` retries on a non-fast-forward reject by
  integrating the remote first — no more silent lost updates across machines.
- **Observability**: `sync.sh status [--json]` (read-only state), `--dry-run` for
  pull/push, and a one-line receipt on every pull/push (which commit, files
  changed, what stayed local, or why it aborted).
- **No hung hooks**: git runs with `GIT_TERMINAL_PROMPT=0` (SSH batch mode), so a
  missing credential fails fast instead of waiting on a prompt.
- **Versioning**: `sync.sh version`, `VERSION` file, version shown in the install
  banner and `status --json`.
- Dual-mode per-project memory: `central` (default, safe for public repos) and
  opt-in `in-project`, with a public-repo leak guard.
- Conflicts are aborted, never committed.

## 0.1.0

- Initial release: sync global `CLAUDE.md` and per-project memory to your own
  private repo via SessionStart (pull) / Stop (push) hooks.
- `local.md` for machine-specific config (gitignored, never synced).
- Cross-OS installers (`install.sh`, `install.ps1`), agent self-install README.
