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
          ┌──────────────────────────────────────────────────────┐
          │  CLAUDE.md   sync.sh   .gitignore                      │
          │  memory/<projectA-slug>/   memory/<projectB-slug>/ ... │
          └──────────────────────────────────────────────────────┘
                    ▲  pull on SessionStart   │ push on Stop
        ┌───────────┴───────────┬─────────────┴───────────┐
   ~/.claude on Mac        ~/.claude on WSL          ~/.claude on Windows
   CLAUDE.md ─┐            CLAUDE.md ─┐              CLAUDE.md ─┐
   memory  ───┴─ symlinks  memory  ──┴─ symlinks    memory  ──┴─ symlinks
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

### 1. Create your own private repo
You need one **empty private** git repo that **you own** — this is where your
rules and memory live. Pick either way:

**With the `gh` CLI (fastest):**
```bash
gh auth login                                   # one-time, if not already
gh repo create my-claude-config --private --clone=false
gh repo view my-claude-config --json sshUrl -q .sshUrl    # copy this URL
```

**With the GitHub website:**
1. Go to <https://github.com/new>.
2. Repository name: `my-claude-config` (any name works).
3. Visibility: select **Private** — this is essential; never make it public.
4. Leave "Add a README / .gitignore / license" **unchecked** (start empty).
5. Click **Create repository**, then copy the SSH URL from the green **Code**
   button, e.g. `git@github.com:you/my-claude-config.git`.

Not on GitHub? Any private git remote works — GitLab, Gitea, or self-hosted.
SSH URLs are recommended so pushes don't prompt for a password.

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

### 5. (Optional) Sync more than one project's memory
Claude stores memory **per project**. To sync several projects, run the installer
once per project — each gets its own `memory/<slug>/` folder in your repo, so
they never mix:
```bash
./install.sh git@github.com:you/my-claude-config.git ~/Projects        # project A
./install.sh git@github.com:you/my-claude-config.git ~/work/api-server  # project B
```
`CLAUDE.md` (global rules) is shared by all projects; each project keeps its own
memory. The `<slug>` is just the project's absolute path with `/` → `-`, so the
same project on another machine (a different absolute path) maps to its own
folder — run the installer there with that machine's path to link them up.

---

## What the installer does

1. Clones your private repo to `~/.claude-autosync` (a fixed, OS-stable location).
2. On first run, scaffolds `CLAUDE.md` + `memory/` from `templates/`.
3. Symlinks `~/.claude/CLAUDE.md` → `~/.claude-autosync/CLAUDE.md` (backs up any
   existing file first).
4. Symlinks `~/.claude/projects/<slug>/memory` → `~/.claude-autosync/memory/<slug>`
   (merges and backs up any existing memory, non-destructively). Run again with a
   different project path to add more projects — each gets its own folder.
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
  We symlink this dir to `~/.claude-autosync/memory/<slug>/` so memory syncs too.
  Each project has its own folder — to sync multiple projects, run the procedure
  once per project path.
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
`~/.claude/CLAUDE.md`. Memory is synced per project (one `memory/<slug>/` folder
each); run the installer once per project you want to include.

**How is per-project memory kept separate?** Each project's memory maps to its
own `memory/<slug>/` folder in your repo, keyed by the project's path-derived
slug, so two projects never overwrite each other's memory.

**GitLab / Gitea / self-hosted?** Yes — any git remote URL works.

## License

MIT — see [LICENSE](LICENSE).
