# Changelog

All notable changes to claude-autosync. Versions follow [SemVer](https://semver.org/).

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
