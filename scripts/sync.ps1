# claude-autosync - sync driver (Windows). Invoked by Claude Code hooks.
#   sync.ps1 pull            pull latest (SessionStart)
#   sync.ps1 push            commit + push local changes (Stop)
#   sync.ps1 status          report state (read-only)
# Fail-open, but reports conflicts / push failures. A lock dir serializes
# concurrent sessions; push retries on a non-fast-forward reject (no lost update).
param([string]$Mode = "pull")

$AutosyncVersion = "0.3.0"
# Never let git block a Claude session waiting on a credential prompt.
$env:GIT_TERMINAL_PROMPT = "0"
$SyncDir = Join-Path $env:USERPROFILE ".claude-autosync"
$Stamp = Get-Date -Format "yyyyMMddHHmmss"
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
# Materialize synced skills/commands into ~/.claude (idempotent). A name that
# collides with a real local item is backed up (timestamped), never clobbered.
# Removal of an item upstream is handled by Recover-Removed, not here.
function Link-SyncedItems {
    $claude = Join-Path $env:USERPROFILE ".claude"
    foreach ($sub in @("skills", "commands")) {
        $repo = Join-Path $SyncDir $sub
        $dest = Join-Path $claude $sub
        if (-not (Test-Path $repo)) { continue }
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Get-ChildItem -Force $repo -ErrorAction SilentlyContinue | ForEach-Object {
            $target = Join-Path $dest $_.Name
            $cur = Get-Item $target -ErrorAction SilentlyContinue
            if ($cur -and $cur.LinkType) {
                if ($cur.Target -ne $_.FullName) {
                    Remove-Item $target -Force -Recurse; New-Item -ItemType SymbolicLink -Path $target -Target $_.FullName | Out-Null
                }
            } elseif (Test-Path $target) {
                Move-Item $target "$target.local.bak.$Stamp" -Force
                New-Item -ItemType SymbolicLink -Path $target -Target $_.FullName | Out-Null
                Write-Error "claude-autosync: collision: local $($_.Name) kept as $($_.Name).local.bak.$Stamp"
            } else {
                New-Item -ItemType SymbolicLink -Path $target -Target $_.FullName | Out-Null
            }
        }
    }
}

# Mirror of bash recover_removed: an item removed upstream leaves a dangling
# symlink. If its removal commit was a 'purge:' delete it; otherwise recover a
# byte-exact local copy from the pre-pull commit (git archive -> tar). Only ever
# touches OUR symlinks (pointing into $SyncDir). If recovery fails, the symlink is
# left untouched (never destroys unique content - it remains in git history).
function Recover-Removed($prev, $new) {
    if ($prev -eq $new) { return }
    $claude = Join-Path $env:USERPROFILE ".claude"
    $purged = @(git log --format='%s' "$prev..$new" 2>$null |
        ForEach-Object { if ($_ -match '^purge: [a-z]+ (.+)$') { $matches[1] } })
    $raw = (git diff --no-renames --name-status -z "$prev" "$new" -- skills commands 2>$null) -join "`n"
    $fields = $raw -split "`0" | Where-Object { $_ -ne "" }
    $seen = @{}
    for ($i = 0; ($i + 1) -lt $fields.Count; $i += 2) {
        if ($fields[$i] -ne "D") { continue }
        $path = $fields[$i + 1]
        if ($path -like "skills/*") {
            $name = (($path -replace '^skills/', '') -split '/')[0]; $type = "skill"
            $rel = "skills/$name"; $dest = Join-Path $claude ("skills\" + $name)
        } elseif ($path -like "commands/*") {
            $name = ($path -replace '^commands/', '') -replace '\.md$', ''; $type = "command"
            $rel = "commands/$name.md"; $dest = Join-Path $claude ("commands\" + $name + ".md")
        } else { continue }
        $key = "$type/$name"; if ($seen[$key]) { continue }; $seen[$key] = $true
        $cur = Get-Item $dest -ErrorAction SilentlyContinue
        if (-not ($cur -and $cur.LinkType)) { continue }       # only act on a symlink...
        if ($cur.Target -notlike "$SyncDir*") { continue }     # ...that points into our repo
        if ($purged -contains $name) { Remove-Item $dest -Force -Recurse -ErrorAction SilentlyContinue; continue }
        $tmp = Join-Path $env:TEMP ("cas-recover-" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        $arc = "$tmp.tar"
        git archive -o $arc "$prev" "$rel" 2>$null            # -o avoids the binary-corrupting PS pipe
        if (Test-Path $arc) { & tar -x -f $arc -C $tmp 2>$null; Remove-Item $arc -Force -ErrorAction SilentlyContinue }
        $src = Join-Path $tmp ($rel -replace '/', '\')
        if (Test-Path $src) {
            Remove-Item $dest -Force -Recurse -ErrorAction SilentlyContinue
            New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
            Move-Item $src $dest -Force
        }
        Remove-Item $tmp -Force -Recurse -ErrorAction SilentlyContinue
    }
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
    if ($Mode -eq "link") { Link-SyncedItems; exit 0 }
    if ($Mode -eq "pull") {
        $weHoldLock = Acquire-Lock
        if (-not $weHoldLock) { Write-Error "claude-autosync: pull skipped (sync in progress)"; exit 0 }
        $prev = (git rev-parse --short HEAD 2>$null)
        if (Integrate) {
            $new = (git rev-parse --short HEAD 2>$null)
            Recover-Removed $prev $new
            Link-SyncedItems
            Write-Host "claude-autosync: pull ok"
        }
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
