# claude-autosync

Keep your **Claude Code global rules (`CLAUDE.md`) and memory in sync across all
your machines** — Mac, Linux, WSL, Windows — through **your own private git repo**.

This repository is just the **tool** (scripts + templates). It contains **no
personal data**. Your actual rules and memory live in a **private repo you own**,
so nothing sensitive is ever public.

---

## Why

Claude Code reads global rules from `~/.claude/CLAUDE.md` and stores memory under
`~/.claude/projects/<project>/memory/`. These live only on one machine. If you
use Claude on a laptop, a desktop, and a server, each has its own disconnected
brain. `claude-autosync` symlinks both into one git repo and auto-syncs it:

- **SessionStart hook** → `git pull` (you start a session with the latest rules)
- **Stop hook** → `git commit && git push` (changes propagate when you finish)

```
                 your PRIVATE repo (github.com/you/my-claude-config)
                 ┌───────────────────────────────────────────────┐
                 │  CLAUDE.md   memory/   sync.sh   .gitignore     │
                 └───────────────────────────────────────────────┘
                    ▲  pull on SessionStart   │ push on Stop
        ┌───────────┴───────────┬─────────────┴───────────┐
   ~/.claude on Mac        ~/.claude on WSL          ~/.claude on Windows
   CLAUDE.md ─┐            CLAUDE.md ─┐              CLAUDE.md ─┐
   memory/  ──┴─ symlinks  memory/  ──┴─ symlinks   memory/  ──┴─ symlinks
   local.md (per-machine, NEVER synced)
```

---

## Security model — read this first

- **You use YOUR OWN private repo.** Do not point this at a shared or public repo.
  Create an **empty private repo** on your GitHub (or GitLab/Gitea/self-hosted).
- **This public tool repo stays data-free.** It only ships scripts and blank
  templates. Never commit your real `CLAUDE.md`, memory, or `local.md` here.
- **`local.md` is never synced.** Machine-specific paths, SSH hosts, LAN IPs, and
  anything you don't want in git go in `~/.claude-autosync/local.md`, which is
  gitignored. `CLAUDE.md` imports it via `@local.md`, so each machine has its own.
- **Your synced repo is still private, but treat it as such**: don't put raw
  secrets (API keys, passwords) in `CLAUDE.md` or memory. Use `local.md` or a
  real secrets manager for those.

---

## Quick start

### 1. Create your private repo
On your own GitHub, create a new **empty private** repository, e.g.
`my-claude-config`. Copy its clone URL (SSH recommended).

### 2. Get this tool
```bash
git clone https://github.com/<you>/claude-autosync.git
cd claude-autosync
```

### 3. Install (per machine)

**macOS / Linux / WSL**
```bash
./install.sh <your-private-repo-url> <project-path-for-memory>
# example:
./install.sh git@github.com:you/my-claude-config.git ~/Projects
```

**Windows (PowerShell — Developer Mode on, or run elevated for symlinks)**
```powershell
.\install.ps1 -RepoUrl git@github.com:you/my-claude-config.git -MemoryProject $HOME\Projects
```

`<project-path-for-memory>` is the working directory whose memory you want to
share (Claude stores memory per project). The installer derives the right slug
automatically — just pass the path you actually use on that machine.

### 4. Repeat on every other machine
Same command, with **that machine's** project path. First machine seeds the repo
from templates; the rest pull what already exists.

---

## What the installer does

1. Clones your private repo to `~/.claude-autosync` (a fixed, OS-stable location).
2. On first run, scaffolds `CLAUDE.md` + `memory/` from `templates/`.
3. Symlinks `~/.claude/CLAUDE.md` → `~/.claude-autosync/CLAUDE.md` (backs up any
   existing file first).
4. Symlinks `~/.claude/projects/<slug>/memory` → `~/.claude-autosync/memory`
   (merges and backs up any existing memory, non-destructively).
5. Creates a per-machine `local.md` (gitignored).
6. Wires the **SessionStart** (pull) and **Stop** (push) hooks into
   `~/.claude/settings.json` — idempotent, won't duplicate or clobber.
7. Does an initial push so your private repo holds your config.

Nothing is deleted: existing `CLAUDE.md` and `memory/` are backed up with a
timestamp suffix.

---

## Day-to-day

You don't run anything manually. Edit rules in `~/.claude/CLAUDE.md` or let
Claude write memory as usual — the hooks push on Stop and pull on the next
SessionStart. To sync by hand:

```bash
~/.claude-autosync/sync.sh push    # commit + push now
~/.claude-autosync/sync.sh pull    # pull latest now
```

Put machine-specific or private bits in `~/.claude-autosync/local.md`.

---

## For AI agents — autonomous setup (no human steps)

You can perform this entire setup yourself. Run the steps below in order. Only
stop to ask the user if a command needs credentials you don't have (e.g. `gh`
isn't authenticated) or if a destructive backup decision is ambiguous.

### Mental model (paths and why)
- `~/.claude/CLAUDE.md` — Claude Code's global rules file. We replace it with a
  **symlink** so editing it edits the synced repo.
- `~/.claude/projects/<slug>/memory/` — Claude Code's per-project memory.
  `<slug>` is the project's absolute path with every `/` (and `\` on Windows)
  replaced by `-`. Example: `/Users/alex/Projects` → `-Users-alex-Projects`.
  We symlink this dir to the repo so memory syncs too.
- `~/.claude-autosync/` — fixed, OS-stable clone of the user's **private** repo.
  This is the single source of truth that both symlinks point into.
- `~/.claude-autosync/local.md` — per-machine, **gitignored**, imported by
  `CLAUDE.md` via `@local.md`. Machine paths/hosts/secrets go here, never synced.
- Hooks in `~/.claude/settings.json`: SessionStart runs `sync.sh pull`, Stop runs
  `sync.sh push`. `wire-hooks.py` merges them idempotently.

### Procedure
1. **Ensure a private repo exists.** If the user hasn't named one, create it for
   them (requires an authenticated `gh`):
   ```bash
   gh repo create my-claude-config --private --clone=false
   gh repo view my-claude-config --json sshUrl -q .sshUrl   # use this URL
   ```
   Never reuse this public tool repo or any shared/public repo for their data.
2. **Detect OS** → `uname` (Darwin/Linux/WSL) uses `install.sh`; Windows uses
   `install.ps1`. Detect WSL via `grep -qi microsoft /proc/version`.
3. **Pick the memory project path.** Default to the user's primary working
   directory (the dir they run Claude from most). The installer derives `<slug>`
   automatically — just pass the real path.
4. **Run the installer:**
   ```bash
   ./install.sh <private-repo-ssh-url> <project-path>
   ```
   It is non-destructive: existing `CLAUDE.md`/`memory` are backed up with a
   timestamp before being symlinked.
5. **Verify** (all must hold):
   ```bash
   readlink ~/.claude/CLAUDE.md                 # -> ~/.claude-autosync/CLAUDE.md
   readlink ~/.claude/projects/<slug>/memory    # -> ~/.claude-autosync/memory
   python3 -c "import json;h=json.load(open('$HOME/.claude/settings.json'))['hooks'];print('SessionStart' in h and 'Stop' in h)"
   git -C ~/.claude-autosync log --oneline -1   # initial push exists
   ```
6. **Tell the user** what changed: secrets and machine-specific paths belong in
   `~/.claude-autosync/local.md` (never synced); the synced repo must stay
   private. On any other machine, re-run step 4 with that machine's project path.

You do not need `install.sh` if a shell is unavailable: replicate steps 1–7 of
[What the installer does](#what-the-installer-does) directly — clone the repo to
`~/.claude-autosync`, scaffold from `templates/`, create the two symlinks, copy
`scripts/sync.sh`, run `scripts/wire-hooks.py`, then `sync.sh push`.

Never commit the user's personal data to this public tool repo.

---

## Uninstall

```bash
rm ~/.claude/CLAUDE.md && cp ~/.claude/CLAUDE.md.bak.* ~/.claude/CLAUDE.md   # restore backup
rm ~/.claude/projects/<slug>/memory                                          # remove symlink
# then remove the SessionStart/Stop entries from ~/.claude/settings.json
```

Your data remains safe in your private repo and in the timestamped backups.

---

## FAQ

**Can two machines conflict?** Pull-on-start / push-on-stop keeps overlap small.
If a push is rejected, run `sync.sh pull` (it merges) then `sync.sh push`. For
heavy concurrent editing, sync manually.

**Does it sync project-local `CLAUDE.md` files?** No — only the global
`~/.claude/CLAUDE.md` and one project's memory. That's the cross-machine "brain".

**GitLab / Gitea / self-hosted?** Yes — any git remote URL works.

## License

MIT — see [LICENSE](LICENSE).
