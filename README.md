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
          │  memory/<projectA-name>/   memory/<projectB-name>/ ... │
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

### 5. (Optional) Add more projects — `memory-add.sh`
Claude stores memory **per project**. Add each project with `memory-add.sh`,
which supports two modes. **`central` is the default and is safe for any repo,
including public ones.**

```bash
# central (default): memory stays in YOUR private repo, never touches the project
./scripts/memory-add.sh ~/work/api-server

# central + shared alias: same folder across machines (see "Mixed projects" below)
./scripts/memory-add.sh ~/work/api-server --name api

# in-project: memory lives in <project>/claude-memory/, travels with the project's
# own git. Only for PRIVATE repos — refused on public ones.
./scripts/memory-add.sh ~/work/team-app --mode in-project
```

`CLAUDE.md` (global rules) is always shared by all projects; only memory is
per-project. See [Mixed public + private projects](#mixed-public--private-projects)
for how to choose a mode.

---

## What the installer does

1. Clones your private repo to `~/.claude-autosync` (a fixed, OS-stable location).
2. On first run, scaffolds `CLAUDE.md` + `memory/` from `templates/`.
3. Symlinks `~/.claude/CLAUDE.md` → `~/.claude-autosync/CLAUDE.md` (backs up any
   existing file first).
4. Symlinks `~/.claude/projects/<slug>/memory` → `~/.claude-autosync/memory/<name>`
   (`<name>` defaults to the project basename; merges and backs up any existing
   memory, non-destructively). Run again with a different project path to add more
   projects — each gets its own folder.
5. Creates a per-machine `local.md` (gitignored).
6. Wires the **SessionStart** (pull) and **Stop** (push) hooks into
   `~/.claude/settings.json` — idempotent, won't duplicate or clobber.
7. Does an initial push so your private repo holds your config.

Nothing is deleted: existing `CLAUDE.md` and `memory/` are backed up with a
timestamp suffix.

---

## Mixed public + private projects

If you work on both **public** repos (open source) and **private** repos, the
risk is leaking personal memory into a public project. `claude-autosync` is
**safe by default** and blocks the dangerous case automatically.

### Decision rule (the tool enforces it)

| Project | Repo visibility | Want to share memory with a team? | Mode |
|---|---|---|---|
| Open source / public | **public** | — | **central** (in-project is refused) |
| Personal private | private | no | **central** (default) |
| Team private | private | yes | `in-project` (opt-in) |
| Local, no remote | unknown | — | central; `in-project` needs `--force-in-project` |

- **central** (default, safe): memory lives only in **your** private
  `~/.claude-autosync` repo at `memory/<name>/`, symlinked in. It never writes to
  the project repo, so a public project can never leak your notes.
- **in-project** (opt-in): memory lives in `<project>/claude-memory/` and travels
  with that project's own git via Claude's `autoMemoryDirectory`. Good for sharing
  curated memory with teammates on a **private** repo.

### Automatic leak guard

Before enabling `in-project`, the tool checks the repo's visibility with
`gh repo view`:

- **PUBLIC** → refused, automatically falls back to `central` (with a warning).
- **PRIVATE** → allowed.
- **Unknown** (no `gh`, or no remote) → refused unless you pass
  `--force-in-project`. A confirmed PUBLIC repo is never overridable.

> Even on a private repo, remember it could be made public later. When in doubt,
> use `central` — it is always safe.

### Same project across machines (central mode)

By default the memory folder is named after the project's **basename**, so the
same project shares one folder across machines even when its absolute path differs
(`/Users/me/api` and `/home/me/api` both → `memory/api/`). No flag needed for the
common case.

Two safeguards:
- If two **distinct** local projects share a basename, `memory-add.sh` refuses
  (so their memory can't silently mix) and asks you to pass `--name <unique>`.
- Pass the **same `--name`** on every machine when you want to force a shared
  folder regardless of basenames:
  ```bash
  ./scripts/memory-add.sh <that-machine's-path-to-api> --name api
  ```

## Day-to-day

You don't run anything manually. Edit rules in `~/.claude/CLAUDE.md` or let
Claude write memory as usual — the hooks push on Stop and pull on the next
SessionStart. To sync or inspect by hand:

```bash
~/.claude-autosync/sync.sh push           # commit + push now
~/.claude-autosync/sync.sh pull           # pull latest now
~/.claude-autosync/sync.sh status --json  # read-only: what would sync, without changing anything
~/.claude-autosync/sync.sh version        # print the tool version
```

Put machine-specific or private bits in `~/.claude-autosync/local.md`.

### Receipts, concurrency, and verification

Sync is **fail-open** (a hiccup never blocks your session) but **not fail-silent**:

- Every `pull`/`push` prints a one-line **receipt** to stderr — which commit
  rules loaded from, files changed, what stayed local, or why a sync aborted.
  This catches the two scary failures: stale rules silently winning, and personal
  memory silently becoming shared.
- `status --json` is read-only — Claude or you can verify state (ahead/behind,
  dirty, conflict, `local_only`, current commit) **without** mutating anything.
- A lock serializes concurrent sessions on one machine (no `index.lock` races),
  and `push` **retries on a non-fast-forward reject** by integrating the remote
  first — so a second machine's push can't silently lose your changes.
- Merge conflicts are **aborted**, never committed; resolve them in
  `~/.claude-autosync` and run `sync.sh push`.

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
  Per-project memory is added with `scripts/memory-add.sh`, which has two modes:
  - **central** (default, safe): symlink that dir to `~/.claude-autosync/memory/<name>/`.
    Never touches the project repo — safe for public projects. Use `--name <alias>`
    to share one folder for the same project across machines.
  - **in-project** (opt-in): set Claude's `autoMemoryDirectory` to
    `<project>/claude-memory/` so memory rides the project's own git. Only for
    **private** repos; `memory-add.sh` refuses it on public repos (verified via
    `gh repo view`).
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
4. **Run the installer** (sets up CLAUDE.md, hooks, and the first project's memory
   in safe `central` mode):
   ```bash
   ./install.sh <private-repo-ssh-url> <project-path>
   ```
   It is non-destructive: existing `CLAUDE.md`/`memory` are backed up with a
   timestamp before being symlinked. For each **additional** project, run
   `./scripts/memory-add.sh <path>`. Only choose `--mode in-project` after
   confirming that project's repo is **private** — the script enforces this, but
   default to `central` (always safe) unless the user wants team-shared memory.
5. **Verify** (all must hold):
   ```bash
   ~/.claude-autosync/sync.sh status --json     # read-only state: branch/head/ahead/behind/conflict/local_only
   readlink ~/.claude/CLAUDE.md                 # -> ~/.claude-autosync/CLAUDE.md
   readlink ~/.claude/projects/<slug>/memory    # -> ~/.claude-autosync/memory/<name>
   python3 -c "import json;h=json.load(open('$HOME/.claude/settings.json'))['hooks'];print('SessionStart' in h and 'Stop' in h)"
   ```
   Parse the `status --json` output to confirm the push landed (`ahead` is 0,
   `in_conflict` is false) and that `local_only` lists `local.md` (kept private).
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
If both machines edit the same file before syncing, `sync.sh pull` detects the
merge conflict and **aborts automatically** (it never commits conflict markers),
printing a notice to resolve it manually in `~/.claude-autosync`. Run
`git pull` / `git mergetool` there to reconcile, then `sync.sh push`. The first
push also self-configures upstream tracking, so sync works without any git tweaks.

**Does it sync project-local `CLAUDE.md` files?** No — only the global
`~/.claude/CLAUDE.md`. Memory is added per project via `memory-add.sh`.

**Is it safe to use on public/open-source projects?** Yes — the default `central`
mode keeps memory in your own private repo and never writes to the project. The
`in-project` mode (which does write into the project) is automatically refused on
public repos. See [Mixed public + private projects](#mixed-public--private-projects).

**How is per-project memory kept separate?** In `central` mode each project maps
to its own `memory/<name>/` folder in your private repo. In `in-project` mode it
lives in that project's `claude-memory/`. Either way, projects never mix.

**GitLab / Gitea / self-hosted?** Yes — any git remote URL works.

**Windows support?** `install.ps1` covers the full global sync (CLAUDE.md, hooks,
and one project's memory in central mode) — symlinks need Developer Mode on or an
elevated terminal. The richer per-project tooling (`memory-add.sh`: extra
projects, `--name` aliases, in-project mode, and the public-repo leak guard) is
currently **bash-only**; on Windows run it under WSL, or stick to the single
central project that `install.ps1` sets up.

## License

MIT — see [LICENSE](LICENSE).
