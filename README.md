# claude-autosync

![version](https://img.shields.io/badge/version-0.3.0-blue) ![license](https://img.shields.io/badge/license-MIT-green)

> **Version 0.3.0** — check yours with `sync.sh version`. See [CHANGELOG](CHANGELOG.md).

Keep your **Claude Code global rules (`CLAUDE.md`), memory, and selected
skills/commands in sync across all your machines** — Mac, Linux, WSL, Windows —
through **your own private git repo**.

This repository is just the **tool** (scripts + templates). It contains **no
personal data**. Your actual rules, memory, and skills live in a **private repo
you own**, so nothing sensitive is ever public.

---

## For AI agents — autonomous setup (start here)

**If you are an AI agent reading this to set up the user's machine, this section
is for you — do the whole thing yourself.** Run the steps in order. Only stop to
ask the user when a command needs credentials you don't have (e.g. `gh` isn't
authenticated) or a destructive backup decision is genuinely ambiguous.

### Mental model (paths and why)
- `~/.claude/CLAUDE.md` — Claude Code's global rules. We replace it with a
  **symlink** so editing it edits the synced repo.
- `~/.claude/projects/<slug>/memory/` — per-project memory. `<slug>` is the
  project's absolute path with every `/` (and `\` on Windows) replaced by `-`,
  e.g. `/Users/alex/Projects` → `-Users-alex-Projects`. Added with
  `scripts/memory-add.sh` (two modes — see below).
- `~/.claude/skills/<name>/` and `~/.claude/commands/<name>.md` — global skills
  and slash commands. **Opt-in**: only items the user explicitly promotes are
  synced (via `scripts/item-sync.sh`); everything else stays local.
- `~/.claude-autosync/` — fixed, OS-stable clone of the user's **private** repo.
  The single source of truth all symlinks point into. Holds `CLAUDE.md`,
  `memory/<name>/`, `skills/<name>/`, `commands/<name>.md`.
- `~/.claude-autosync/local.md` — per-machine, **gitignored**, imported by
  `CLAUDE.md` via `@local.md`. Machine paths/hosts/secrets go here, never synced.
- Hooks in `~/.claude/settings.json`: SessionStart runs `sync.sh pull`, Stop runs
  `sync.sh push`. `wire-hooks.py` merges them idempotently.

### Procedure
1. **Ensure a private repo exists.** If the user hasn't named one, create it
   (needs an authenticated `gh`). Never reuse this public tool repo or any
   shared/public repo for their data.
   ```bash
   gh repo create my-claude-config --private --clone=false
   gh repo view my-claude-config --json sshUrl -q .sshUrl   # use this URL
   ```
2. **Detect OS** → `uname` (Darwin/Linux/WSL) uses `install.sh`; Windows uses
   `install.ps1`. Detect WSL via `grep -qi microsoft /proc/version`.
3. **Pick the memory project path** — default to the dir the user runs Claude
   from most. The installer derives `<slug>` automatically.
4. **Run the installer** (sets up CLAUDE.md, hooks, the first project's memory in
   safe `central` mode, and materializes any already-synced skills/commands):
   ```bash
   ./install.sh <private-repo-ssh-url> <project-path>
   ```
   It is non-destructive: existing files are backed up with a timestamp before
   being symlinked. For each **additional** project run `./scripts/memory-add.sh
   <path>`; choose `--mode in-project` only after confirming that project's repo
   is **private** (the script enforces this, but default to `central`).
5. **Skills & commands materialize automatically.** On a new machine you do **not**
   select anything — `install.sh` and every `sync.sh pull` symlink whatever is
   already in the repo's `skills/` and `commands/` into `~/.claude/`. To **add a
   new** skill/command to the synced set non-interactively (no TUI needed):
   ```bash
   ./scripts/item-sync.sh skill <name>      # e.g. code-review  (a dir in ~/.claude/skills/)
   ./scripts/item-sync.sh command <name>    # e.g. deploy       (deploy.md in ~/.claude/commands/)
   ./scripts/item-sync.sh skill --list      # see synced vs local-only
   ```
   Promote only what the user asks for — skills can contain machine-specific
   paths or private references, so default to leaving them local.
6. **Verify** (all must hold):
   ```bash
   ~/.claude-autosync/sync.sh status --json     # branch/head/ahead/behind/conflict/local_only/synced_skills/synced_commands
   readlink ~/.claude/CLAUDE.md                 # -> ~/.claude-autosync/CLAUDE.md
   readlink ~/.claude/projects/<slug>/memory    # -> ~/.claude-autosync/memory/<name>
   python3 -c "import json;h=json.load(open('$HOME/.claude/settings.json'))['hooks'];print('SessionStart' in h and 'Stop' in h)"
   ```
   Parse `status --json` to confirm the push landed (`ahead` is 0, `in_conflict`
   false) and `local_only` lists `local.md`.
7. **Tell the user** what changed: secrets and machine-specific paths go in
   `~/.claude-autosync/local.md` (never synced); the synced repo must stay
   private. On any other machine, re-run step 4 with that machine's project path.

No shell available? Replicate [What the installer does](#what-the-installer-does)
directly. **Never commit the user's personal data to this public tool repo.**

---

## Security model — read this first

- **You use YOUR OWN private repo.** Do not point this at a shared or public repo.
  Create an **empty private repo** on your GitHub (or GitLab/Gitea/self-hosted).
- **This public tool repo stays data-free.** It only ships scripts and blank
  templates. Never commit your real `CLAUDE.md`, memory, skills, or `local.md` here.
- **`local.md` is never synced.** Machine-specific paths, SSH hosts, LAN IPs, and
  anything you don't want in git go in `~/.claude-autosync/local.md`, which is
  gitignored. `CLAUDE.md` imports it via `@local.md`, so each machine has its own.
- **Skills/commands are opt-in.** Nothing under `~/.claude/skills` or
  `~/.claude/commands` syncs until you promote it, so a machine-specific or
  private skill never leaves the machine by accident.
- **Your synced repo is still private, but treat it as such**: don't put raw
  secrets (API keys, passwords) in `CLAUDE.md`, memory, or skills. Use `local.md`
  or a real secrets manager for those.

---

## Why

Claude Code reads global rules from `~/.claude/CLAUDE.md`, stores memory under
`~/.claude/projects/<project>/memory/`, and loads skills/commands from
`~/.claude/skills` and `~/.claude/commands`. These live only on one machine. If
you use Claude on a laptop, a desktop, and a server, each has its own
disconnected brain. `claude-autosync` symlinks them into one git repo and
auto-syncs it:

- **SessionStart hook** → `git pull` (you start a session with the latest setup)
- **Stop hook** → `git commit && git push` (changes propagate when you finish)

```
          your PRIVATE repo (github.com/you/my-claude-config)
          ┌──────────────────────────────────────────────────────┐
          │  CLAUDE.md   sync.sh   .gitignore                      │
          │  memory/<projectA>/   memory/<projectB>/  ...          │
          │  skills/<name>/  ...   commands/<name>.md  ...         │
          └──────────────────────────────────────────────────────┘
                    ▲  pull on SessionStart   │ push on Stop
        ┌───────────┴───────────┬─────────────┴───────────┐
   ~/.claude on Mac        ~/.claude on WSL          ~/.claude on Windows
   CLAUDE.md ─┐            CLAUDE.md ─┐              CLAUDE.md ─┐
   memory  ───┤            memory  ───┤              memory  ───┤
   skills  ───┴─ symlinks  skills  ───┴─ symlinks    skills  ───┴─ symlinks
   local.md (per-machine, NEVER synced)
```

---

## Quick start

### 1. Create your own private repo
You need one **empty private** git repo that **you own** — this is where your
rules, memory, and skills live. Pick either way:

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
from templates; the rest pull what already exists — including any skills/commands
you've chosen to sync.

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
   memory, non-destructively).
5. **Materializes synced skills/commands** — symlinks every `skills/<name>` and
   `commands/<name>.md` already in the repo into `~/.claude/` (backs up any
   name-colliding local item first).
6. Creates a per-machine `local.md` (gitignored).
7. Wires the **SessionStart** (pull) and **Stop** (push) hooks into
   `~/.claude/settings.json` — idempotent.
8. Does an initial push so your private repo holds your config.

Nothing is deleted: existing files are backed up with a timestamp suffix.

---

## Sync skills & commands (opt-in)

Skills (`~/.claude/skills/<name>/`) and slash commands (`~/.claude/commands/<name>.md`)
sync **only when you choose them** — so a machine-specific or private skill never
leaves the machine by accident. `scripts/item-sync.sh` is the one tool for it.

```bash
# interactive checklist of all skills on a terminal (space toggles, Enter applies)
./scripts/item-sync.sh skill

# or promote by name (works headless / for AI agents)
./scripts/item-sync.sh skill code-review
./scripts/item-sync.sh command deploy

# see what's synced vs local-only
./scripts/item-sync.sh skill --list
```

Promoting **moves** the item into your private repo and symlinks it back, so it
becomes the single source of truth and rides the normal pull/push hooks. On every
other machine it appears automatically on the next `pull` (or `install.sh`).

### Stop syncing one — two intents
| Command | Meaning | This machine | Other machines on next pull |
|---|---|---|---|
| `item-sync.sh skill --unset <name>` | stop syncing, **keep** it | reverts to a local copy | recover their own local copy |
| `item-sync.sh skill --purge <name>` | remove **everywhere** | deleted | deleted |

`--unset` is non-destructive: nobody loses the skill, it just stops being shared.
Use `--purge` for a mistake or something private that shouldn't have been synced
(note: your private repo's **git history still retains it** — a full scrub needs a
history rewrite).

### Collisions
If a new machine already has its **own** different skill of the same name, pull
backs it up to `<name>.local.bak.<timestamp>` before linking the synced one — it
never silently overwrites, and it reports the backup in the receipt.

The interactive checklist uses `whiptail`/`dialog` if present, otherwise a
zero-dependency numbered toggle. On Windows, `item-sync.sh` selection is run under
WSL; native `sync.ps1` still **receives** synced skills/commands automatically on
pull (see the Windows FAQ).

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

---

## Day-to-day

You don't run anything manually. Edit rules in `~/.claude/CLAUDE.md` or let
Claude write memory as usual — the hooks push on Stop and pull on the next
SessionStart. To sync or inspect by hand:

```bash
~/.claude-autosync/sync.sh push           # commit + push now
~/.claude-autosync/sync.sh pull           # pull latest now (also relinks skills/commands)
~/.claude-autosync/sync.sh status --json  # read-only: what would sync, without changing anything
~/.claude-autosync/sync.sh version        # print the tool version
```

Put machine-specific or private bits in `~/.claude-autosync/local.md`.

### Receipts, concurrency, and verification

Sync is **fail-open** (a hiccup never blocks your session) but **not fail-silent**:

- Every `pull`/`push` prints a one-line **receipt** to stderr — which commit
  loaded, files changed, skills relinked, what stayed local, or why a sync aborted.
- `status --json` is read-only — Claude or you can verify state (ahead/behind,
  dirty, conflict, `local_only`, `synced_skills`, `synced_commands`, current
  commit) **without** mutating anything.
- A lock serializes concurrent sessions on one machine (no `index.lock` races),
  and `push` **retries on a non-fast-forward reject** by integrating the remote
  first — so a second machine's push can't silently lose your changes.
- Merge conflicts are **aborted**, never committed; resolve them in
  `~/.claude-autosync` and run `sync.sh push`.
- Git is run with `GIT_TERMINAL_PROMPT=0` (and SSH batch mode), so a missing
  credential fails fast instead of hanging your session on a password prompt.

---

## Uninstall

```bash
rm ~/.claude/CLAUDE.md && cp ~/.claude/CLAUDE.md.bak.* ~/.claude/CLAUDE.md   # restore backup
rm ~/.claude/projects/<slug>/memory                                          # remove memory symlink
# remove synced skill/command symlinks (they just point into ~/.claude-autosync):
find ~/.claude/skills ~/.claude/commands -maxdepth 1 -type l -delete
# then remove the SessionStart/Stop entries from ~/.claude/settings.json
```

Your data remains safe in your private repo and in the timestamped backups.

---

## FAQ

**Can two machines conflict?** Pull-on-start / push-on-stop keeps overlap small.
If both machines edit the same file before syncing, `sync.sh pull` detects the
merge conflict and **aborts automatically** (it never commits conflict markers),
printing a notice to resolve it manually in `~/.claude-autosync`. The first push
also self-configures upstream tracking, so sync works without any git tweaks.

**Does it sync project-local `CLAUDE.md` files?** No — only the global
`~/.claude/CLAUDE.md`. Memory is added per project via `memory-add.sh`.

**Do all my skills sync?** No — skills and commands are **opt-in**. Only the ones
you promote with `item-sync.sh` sync; the rest stay on the machine. Unselecting one
with `--unset` keeps a local copy everywhere; `--purge` removes it everywhere.

**Is it safe to use on public/open-source projects?** Yes — the default `central`
memory mode keeps memory in your own private repo and never writes to the project,
and skills only sync when you explicitly choose them. The `in-project` memory mode
is automatically refused on public repos.

**How is per-project memory kept separate?** In `central` mode each project maps
to its own `memory/<name>/` folder in your private repo. In `in-project` mode it
lives in that project's `claude-memory/`. Either way, projects never mix.

**GitLab / Gitea / self-hosted?** Yes — any git remote URL works.

**Windows support?** `install.ps1` covers the full global sync (CLAUDE.md, hooks,
one project's memory in central mode) and **receives** synced skills/commands on
pull (`sync.ps1` relinks them; a name collision is backed up to `<name>.local.bak`).
The richer tooling — `memory-add.sh` (extra projects, `--name`, in-project, leak
guard) and `item-sync.sh` (choosing which skills/commands to sync) — is currently
**bash-only**; on Windows run it under WSL. Symlinks need Developer Mode on or an
elevated terminal.

## License

MIT — see [LICENSE](LICENSE).
