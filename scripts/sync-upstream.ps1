#!/usr/bin/env pwsh
#requires -Version 7.0
<#
.SYNOPSIS
    Rebase this fork onto upstream/main and refresh the globally installed CLI.

.DESCRIPTION
    1. refuses to run on a dirty working tree
    2. fast-forwards main to upstream/main (and pushes it to origin)
    3. rebases feat/pi-desktop onto the new main
    4. runs pnpm install only when the lockfile moved or node_modules is missing
    5. rebuilds core + cli and mirrors dist into the global npm package
    6. runs the PI-Desktop test files

    Conflicts stop the script with the conflicted paths printed; nothing is
    discarded, so `git rebase --continue` (or `--abort`) is the next step.

.PARAMETER SkipInstall
    Do not touch the globally installed CLI.

.PARAMETER SkipTests
    Do not run the test files.

.EXAMPLE
    pwsh ./scripts/sync-upstream.ps1
.EXAMPLE
    pwsh ./scripts/sync-upstream.ps1 -SkipInstall -SkipTests
#>
param(
    [switch]$SkipInstall,
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"
$branch = "feat/pi-desktop"
$repo = Split-Path -Parent $PSScriptRoot

function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
    & git -C $repo @GitArgs
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArgs -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Invoke-Step {
    param([string]$Message, [scriptblock]$Body)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
    & $Body
}

function Copy-BuildOutput {
    param([string]$Source, [string]$Destination)
    if (-not (Test-Path $Source)) { throw "missing build output: $Source" }
    if (-not (Test-Path $Destination)) { throw "target package not installed: $Destination (run: npm install -g @mindfoldhq/trellis --force)" }
    & robocopy $Source $Destination /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }
    Write-Host ("    mirrored {0} -> {1}" -f $Source, $Destination)
}

Push-Location $repo
try {
    Invoke-Step "Checking the working tree" {
        $status = @(& git -C $repo status --porcelain) |
            Where-Object { $_ -notmatch '^\s*[Mm? ]{1,2}\s+(docs-site|marketplace)\s*$' }
        if ($status) {
            throw "Working tree is dirty. Commit or stash first:`n$($status -join "`n")"
        }
    }

    $oldMain = (& git -C $repo rev-parse main).Trim()

    Invoke-Step "Fetching upstream" {
        & git -C $repo fetch upstream --prune --quiet
        if ($LASTEXITCODE -ne 0) { throw "git fetch upstream failed" }
        $behind = [int](& git -C $repo rev-list --count "main..upstream/main")
        Write-Host "    upstream commits not in main: $behind"
        if ($behind -gt 0) {
            Invoke-Git checkout main
            Invoke-Git merge --ff-only upstream/main
            Invoke-Git push origin main
        }
    }

    Invoke-Step "Rebasing $branch onto main" {
        Invoke-Git checkout $branch
        $head = (& git -C $repo rev-parse HEAD).Trim()
        $base = (& git -C $repo merge-base HEAD main).Trim()
        $mainTip = (& git -C $repo rev-parse main).Trim()
        if ($base -eq $mainTip) {
            Write-Host "    already based on main ($($head.Substring(0, 7)))"
        } else {
            & git -C $repo rebase main
            if ($LASTEXITCODE -ne 0) {
                $conflicts = @(& git -C $repo diff --name-only --diff-filter=U)
                Write-Host ""
                Write-Host "Rebase stopped on conflicts:" -ForegroundColor Yellow
                $conflicts | ForEach-Object { Write-Host "    $_" }
                Write-Host "Resolve them, then: git rebase --continue   (or: git rebase --abort)"
                exit 1
            }
            Write-Host "    rebased $(@(& git -C $repo rev-list --count 'main..HEAD')) commit(s) onto main"
        }
    }

    Invoke-Step "Installing dependencies" {
        $lockMoved = @(& git -C $repo diff --name-only $oldMain main -- pnpm-lock.yaml)
        if ($lockMoved -or -not (Test-Path (Join-Path $repo "node_modules"))) {
            & pnpm install
            if ($LASTEXITCODE -ne 0) { throw "pnpm install failed" }
        } else {
            Write-Host "    lockfile unchanged, skipping"
        }
    }

    Invoke-Step "Building core + cli" {
        & pnpm build
        if ($LASTEXITCODE -ne 0) { throw "pnpm build failed" }
    }

    if (-not $SkipInstall) {
        Invoke-Step "Refreshing the globally installed CLI" {
            $npmRoot = (& npm root -g).Trim()
            $packageRoot = Join-Path $npmRoot "@mindfoldhq/trellis"
            Copy-BuildOutput (Join-Path $repo "packages/cli/dist") (Join-Path $packageRoot "dist")
            Copy-BuildOutput (Join-Path $repo "packages/core/dist") (Join-Path $packageRoot "node_modules/@mindfoldhq/trellis-core/dist")
        }
    }

    if (-not $SkipTests) {
        Invoke-Step "Running the PI-Desktop tests" {
            Push-Location (Join-Path $repo "packages/cli")
            try {
                & npx vitest run --maxWorkers=3 test/commands/pi-desktop.test.ts test/templates/pi-desktop.test.ts test/registry-invariants.test.ts
                if ($LASTEXITCODE -ne 0) { throw "tests failed" }
            } finally {
                Pop-Location
            }
        }
    }

    Write-Host ""
    Write-Host "==> Done" -ForegroundColor Green
    Write-Host ("    {0}" -f ((& git -C $repo log --oneline -1) -join ""))
    Write-Host ("    upstream/main: {0}" -f (& git -C $repo log --oneline -1 upstream/main))
    if (-not $SkipInstall) { Write-Host ("    trellis --version: {0}" -f (& trellis --version)) }
} finally {
    Pop-Location
}
