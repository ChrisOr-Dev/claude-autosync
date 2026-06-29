# claude-autosync - sync driver (Windows). Invoked by Claude Code hooks.
#   sync.ps1 pull            pull latest (SessionStart)
#   sync.ps1 push            commit + push local changes (Stop)
#   sync.ps1 status          report state (read-only)
# Fail-open, but reports conflicts / push failures. A lock dir serializes
# concurrent sessions; push retries on a non-fast-forward reject (no lost update).
param([string]$Mode = "pull")

$AutosyncVersion = "0.2.0"
# Never let git block a Claude session waiting on a credential prompt.
$env:GIT_TERMINAL_PROMPT = "0"
$SyncDir = Join-Path $env:USERPROFILE ".claude-autosync"
if (-not (Test-Path (Join-Path $SyncDir ".git"))) { exit 0 }
Set-Location $SyncDir
$LockDir = Join-Path $SyncDir ".sync.lock"

$br = (git symbolic-ref --short HEAD 2>$null); if (-not $br) { $br = "main" }

function In-Conflict {
    $gd = (git rev-parse --git-dir 2>$null)
    return ($gd -and (Test-Path (Join-Path $gd "MERGE_HEAD")) -and (git ls-files -u 2>$null))
}
function Integrate {
    git pull --quiet --no-rebase 2>$null
    if ($LASTEXITCODE -ne 0) { git pull --quiet --no-rebase origin $br 2>$null }
    if (In-Conflict) { git merge --abort 2>$null; return $false }
    return $true
}
function Acquire-Lock {
    for ($i = 0; $i -lt 10; $i++) {
        try { New-Item -ItemType Directory -Path $LockDir -ErrorAction Stop | Out-Null; return $true } catch {}
        # steal a stale lock (>2 min); tolerate it vanishing mid-check
        try {
            $age = (Get-Date) - (Get-Item $LockDir -ErrorAction Stop).CreationTime
            if ($age.TotalMinutes -gt 2) { Remove-Item $LockDir -Force -Recurse -ErrorAction SilentlyContinue; continue }
        } catch { continue }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

$weHoldLock = $false
try {
    if ($Mode -eq "status") {
        $head = (git rev-parse --short HEAD 2>$null)
        Write-Host "claude-autosync: v$AutosyncVersion branch=$br head=$head"
        exit 0
    }
    if ($Mode -eq "pull") {
        $weHoldLock = Acquire-Lock
        if (-not $weHoldLock) { Write-Error "claude-autosync: pull skipped (sync in progress)"; exit 0 }
        if (Integrate) { Write-Host "claude-autosync: pull ok" }
        else { Write-Error "claude-autosync: pull CONFLICT aborted - resolve in $SyncDir" }
    } elseif ($Mode -eq "push") {
        $weHoldLock = Acquire-Lock
        if (-not $weHoldLock) { Write-Error "claude-autosync: push skipped (sync in progress)"; exit 0 }
        git add -A 2>$null
        git diff --cached --quiet 2>$null
        if ($LASTEXITCODE -ne 0) {
            $stamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
            git commit -q -m "sync: $env:COMPUTERNAME $stamp" 2>$null
        }
        $pushed = $false
        for ($a = 0; $a -lt 3; $a++) {
            git push --quiet 2>$null
            if ($LASTEXITCODE -eq 0) { $pushed = $true; break }
            git push -u origin $br --quiet 2>$null
            if ($LASTEXITCODE -eq 0) { $pushed = $true; break }
            if (-not (Integrate)) { Write-Error "claude-autosync: push CONFLICT - resolve in $SyncDir"; break }
        }
        if (-not $pushed) { Write-Error "claude-autosync: push FAILED after retries (will retry next session)" }
    }
} catch {} finally {
    if ($weHoldLock -and (Test-Path $LockDir)) { Remove-Item $LockDir -Force -Recurse 2>$null }
}
exit 0
