# claude-autosync - sync driver (Windows). Invoked by Claude Code hooks.
#   sync.ps1 pull   -> pull latest from your private repo (SessionStart)
#   sync.ps1 push   -> commit + push local changes (Stop)
# Silent and non-fatal: never block a Claude session.
param([string]$Mode = "pull")

$SyncDir = Join-Path $env:USERPROFILE ".claude-autosync"
if (-not (Test-Path (Join-Path $SyncDir ".git"))) { exit 0 }
Set-Location $SyncDir

try {
    if ($Mode -eq "pull") {
        git pull --quiet --no-rebase 2>$null
    } elseif ($Mode -eq "push") {
        git add -A 2>$null
        git diff --cached --quiet 2>$null
        if ($LASTEXITCODE -ne 0) {
            $stamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
            git commit -q -m "sync: $env:COMPUTERNAME $stamp" 2>$null
            git push --quiet 2>$null
        }
    }
} catch {}
exit 0
