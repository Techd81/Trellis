#!/usr/bin/env pwsh
#requires -Version 7.0
<#
.SYNOPSIS
    Rebase this fork onto upstream/main and refresh the globally installed CLI.

.DESCRIPTION
    1. refuses to run on a dirty working tree
    2. fetches upstream and keeps the fork's main branch pointing at it
    3. rebases feat/pi-desktop onto upstream/main
    4. runs pnpm install only when the lockfile moved or node_modules is missing
    5. rebuilds core + cli and mirrors dist into the global npm package
    6. runs the PI-Desktop test files

    Conflicts stop the script with the conflicted paths printed; nothing is
    discarded, so `git rebase --continue` (or `--abort`) is the next step.

    The rebase base is `upstream/main`, never a local `main`: this checkout is a
    git worktree, where the fork's `main` branch is usually checked out nowhere.

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
$upstreamBranch = "upstream/main"
$repo = Split-Path -Parent $PSScriptRoot

function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
    & git -C $repo @GitArgs
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArgs -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Get-GitOutput {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
    $output = & git -C $repo @GitArgs
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArgs -join ' ') failed with exit code $LASTEXITCODE"
    }
    return ($output | Out-String).Trim()
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
    if (-not (Test-Path $Destination)) {
        throw "target package not installed: $Destination (run: npm install -g @mindfoldhq/trellis --force)"
    }
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

    Invoke-Step "Fetching upstream" {
        $previous = Get-GitOutput rev-parse $upstreamBranch
        & git -C $repo fetch upstream --prune --quiet
        if ($LASTEXITCODE -ne 0) { throw "git fetch upstream failed" }
        $incoming = [int](Get-GitOutput rev-list --count "HEAD..$upstreamBranch")
        Write-Host "    commits upstream has that $branch lacks: $incoming"
        # Keep the fork's main on upstream without checking it out here.
        & git -C $repo push origin "$upstreamBranch`:refs/heads/main" 2>&1 | Select-Object -Last 1
        if ($LASTEXITCODE -ne 0) { throw "could not fast-forward origin/main" }
        $script:previousUpstream = $previous
    }

    Invoke-Step "Rebasing $branch onto $upstreamBranch" {
        Invoke-Git checkout $branch
        $head = Get-GitOutput rev-parse HEAD
        $tip = Get-GitOutput rev-parse $upstreamBranch
        $base = Get-GitOutput merge-base HEAD $upstreamBranch
        if ($base -eq $tip) {
            Write-Host "    already based on $upstreamBranch ($($head.Substring(0, 7)))"
        } else {
            & git -C $repo rebase $upstreamBranch
            if ($LASTEXITCODE -ne 0) {
                $conflicts = @(& git -C $repo diff --name-only --diff-filter=U)
                Write-Host ""
                Write-Host "Rebase stopped on conflicts:" -ForegroundColor Yellow
                $conflicts | ForEach-Object { Write-Host "    $_" }
                Write-Host "Resolve them, then: git rebase --continue   (or: git rebase --abort)"
                exit 1
            }
            $ahead = Get-GitOutput rev-list --count "$upstreamBranch..HEAD"
            Write-Host "    rebased $ahead commit(s) onto $upstreamBranch"
        }
    }

    Invoke-Step "Checking the docs-site submodule" {
        $recorded = (Get-GitOutput ls-tree HEAD docs-site).Split("`t")[0].Split(" ")[2]
        $docsRepo = Join-Path $repo "docs-site"
        $actual = ((& git -C $docsRepo rev-parse HEAD) | Out-String).Trim()
        if ($actual -ne $recorded) {
            Write-Host "    docs-site is at $($actual.Substring(0, 7)), the branch records $($recorded.Substring(0, 7))" -ForegroundColor Yellow
            Write-Host "    re-apply the docs change: git -C docs-site apply ../docs-site.pi-desktop.patch"
        } else {
            Write-Host "    docs-site matches the recorded commit"
        }
    }

    Invoke-Step "Installing dependencies" {
        $lockMoved = @(& git -C $repo diff --name-only $script:previousUpstream $upstreamBranch -- pnpm-lock.yaml)
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
                # registry-invariants shells out to `python3`, which resolves to a
                # Microsoft Store stub on a stock Windows install. Point it at a real
                # interpreter unless the caller already chose one.
                if (-not $env:PYTHON_CMD) {
                    foreach ($candidate in @("python", "py", "python3")) {
                        $found = Get-Command $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($found -and $found.Source -notmatch "WindowsApps") {
                            $env:PYTHON_CMD = $found.Source
                            break
                        }
                    }
                    if ($env:PYTHON_CMD) {
                        Write-Host "    PYTHON_CMD=$env:PYTHON_CMD"
                    } else {
                        Write-Host "    no real python interpreter found; registry-invariants may fail" -ForegroundColor Yellow
                    }
                }
                & npx vitest run --maxWorkers=3 test/commands/pi-desktop.test.ts test/templates/pi-desktop.test.ts test/registry-invariants.test.ts
                if ($LASTEXITCODE -ne 0) { throw "tests failed" }
            } finally {
                Pop-Location
            }
        }
    }

    Write-Host ""
    Write-Host "==> Done" -ForegroundColor Green
    Write-Host ("    {0}" -f (Get-GitOutput log --oneline -1))
    Write-Host ("    {0}: {1}" -f $upstreamBranch, (Get-GitOutput log --oneline -1 $upstreamBranch))
    if (-not $SkipInstall) { Write-Host ("    trellis --version: {0}" -f (& trellis --version)) }
} finally {
    Pop-Location
}
