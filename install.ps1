# claude-autosync - installer (Windows PowerShell)
#
# Wires this machine to sync Claude Code's global rules (CLAUDE.md) and memory
# to YOUR OWN private git repo. This tool stores no data itself.
#
# Usage:
#   .\install.ps1 -RepoUrl <your-private-repo-url> [-MemoryProject <path>]
#
# Symlinks on Windows need either Developer Mode ON or an elevated terminal.
# ASCII-only on purpose (Win PowerShell 5 ANSI codepage safety).
param(
    [Parameter(Mandatory = $true)][string]$RepoUrl,
    [string]$MemoryProject = $env:USERPROFILE
)
$ErrorActionPreference = "Stop"

$SyncDir   = Join-Path $env:USERPROFILE ".claude-autosync"
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$TplDir    = $PSScriptRoot
$Stamp     = Get-Date -Format "yyyyMMddHHmmss"

Write-Host "=== claude-autosync install ==="
Write-Host "  private repo : $RepoUrl"
Write-Host "  sync dir     : $SyncDir"
Write-Host "  memory for   : $MemoryProject"

# 1. Clone or init the private config repo
if (Test-Path (Join-Path $SyncDir ".git")) {
    Write-Host "[*] Updating existing sync dir..."
    git -C $SyncDir pull --quiet
} else {
    Write-Host "[*] Cloning private repo..."
    git clone $RepoUrl $SyncDir 2>$null
    if (-not (Test-Path (Join-Path $SyncDir ".git"))) {
        Write-Host "[*] Repo empty/unreachable; initializing locally..."
        New-Item -ItemType Directory -Force -Path $SyncDir | Out-Null
        git -C $SyncDir init -q
        git -C $SyncDir remote add origin $RepoUrl
    }
}

# 2. First-run scaffold from templates
$ClaudeMd = Join-Path $SyncDir "CLAUDE.md"
if (-not (Test-Path $ClaudeMd)) {
    Write-Host "[*] Scaffolding CLAUDE.md from templates..."
    Copy-Item (Join-Path $TplDir "templates\CLAUDE.md") $ClaudeMd
    Copy-Item (Join-Path $TplDir "templates\private-gitignore") (Join-Path $SyncDir ".gitignore")
}
Copy-Item (Join-Path $TplDir "scripts\sync.ps1") (Join-Path $SyncDir "sync.ps1") -Force
New-Item -ItemType Directory -Force -Path $ClaudeDir, (Join-Path $SyncDir "memory") | Out-Null

# 3. Per-machine local.md (gitignored, never synced)
$LocalMd = Join-Path $SyncDir "local.md"
if (-not (Test-Path $LocalMd)) {
    Copy-Item (Join-Path $TplDir "templates\local.md.example") $LocalMd
    Write-Host "[*] Created $LocalMd (edit for machine-specific config)"
}

# 4. Symlink global CLAUDE.md
$DestClaude = Join-Path $ClaudeDir "CLAUDE.md"
if ((Test-Path $DestClaude) -and -not ((Get-Item $DestClaude).LinkType)) {
    Move-Item $DestClaude "$DestClaude.bak.$Stamp"
    Write-Host "[*] Backed up existing CLAUDE.md"
}
New-Item -ItemType SymbolicLink -Path $DestClaude -Target $ClaudeMd -Force | Out-Null
Write-Host "[OK] CLAUDE.md linked"

# 5. Symlink this project's memory into its own per-project folder memory\<slug>\
#    (slug = path with / and \ -> -). Re-run per project to sync each one.
$Slug = ($MemoryProject -replace '[\\/]', '-')
$RepoMem = Join-Path $SyncDir "memory\$Slug"
if (-not (Test-Path $RepoMem)) {
    New-Item -ItemType Directory -Force -Path $RepoMem | Out-Null
    Copy-Item (Join-Path $TplDir "templates\memory\MEMORY.md") (Join-Path $RepoMem "MEMORY.md")
}
$MemDest = Join-Path $ClaudeDir "projects\$Slug\memory"
New-Item -ItemType Directory -Force -Path (Split-Path $MemDest) | Out-Null
if ((Test-Path $MemDest) -and -not ((Get-Item $MemDest).LinkType)) {
    Get-ChildItem (Join-Path $MemDest "*.md") -ErrorAction SilentlyContinue | ForEach-Object {
        $t = Join-Path $RepoMem $_.Name
        if (-not (Test-Path $t)) { Copy-Item $_.FullName $t }
    }
    Move-Item $MemDest "$MemDest.bak.$Stamp"
}
New-Item -ItemType SymbolicLink -Path $MemDest -Target $RepoMem -Force | Out-Null
Write-Host "[OK] memory linked (slug: $Slug)"

# 6. Wire hooks into settings.json
$SettingsPath = Join-Path $ClaudeDir "settings.json"
$SyncPs = Join-Path $SyncDir "sync.ps1"
python "$TplDir\scripts\wire-hooks.py" $SettingsPath "powershell -File `"$SyncPs`"" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Hooks wired into settings.json"
} else {
    Write-Host "[!] Add hooks manually to $SettingsPath :"
    Write-Host "    SessionStart -> powershell -File `"$SyncPs`" pull"
    Write-Host "    Stop         -> powershell -File `"$SyncPs`" push"
}

# 7. Initial push
& powershell -File $SyncPs push

Write-Host ""
Write-Host "=== Done ==="
Write-Host "Edit machine-specific config: $LocalMd"
