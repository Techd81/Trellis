#!/usr/bin/env pwsh
#requires -Version 7.0
<#
.SYNOPSIS
    Merge upstream/main into this fork's main branch and refresh the global CLI.

.DESCRIPTION
    1. refuses to run on a dirty working tree
    2. fetches upstream and merges upstream/main into main
    3. pushes main to origin
    4. runs pnpm install only when the lockfile moved or node_modules is missing
    5. rebuilds core + cli, then installs the packed CLI globally
    6. runs the PI-Desktop test files

    `main` is this fork's product branch: it carries the PI-Desktop adaptation on
    top of upstream, and it is what npm publishes and what GitHub renders.

    Conflicts stop the script with the conflicted paths printed; nothing is
    discarded, so `git merge --abort` or a manual resolution is the next step.

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
$branch = "main"
$upstreamBranch = "upstream/main"
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "lib/fork-common.ps1")

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

Push-Location $repo
try {
    Invoke-Step "Checking the working tree" {
        $status = @(& git -C $repo status --porcelain) |
            Where-Object { $_ -notmatch '^\s*[Mm? ]{1,2}\s+(docs-site|marketplace)\s*$' }
        if ($status) {
            throw "Working tree is dirty. Commit or stash first:`n$($status -join "`n")"
        }
        $current = Get-GitOutput rev-parse --abbrev-ref HEAD
        if ($current -ne $branch) {
            throw "on '$current'; switch to '$branch' first: git checkout $branch"
        }
        $script:beforeMerge = Get-GitOutput rev-parse HEAD
    }

    Invoke-Step "Merging $upstreamBranch" {
        & git -C $repo fetch upstream --prune --quiet
        if ($LASTEXITCODE -ne 0) { throw "git fetch upstream failed" }
        $incoming = [int](Get-GitOutput rev-list --count "HEAD..$upstreamBranch")
        Write-Host "    commits upstream has that $branch lacks: $incoming"
        if ($incoming -eq 0) {
            Write-Host "    already up to date"
        } else {
            & git -C $repo merge --no-edit $upstreamBranch
            if ($LASTEXITCODE -ne 0) {
                $conflicts = @(& git -C $repo diff --name-only --diff-filter=U)
                Write-Host ""
                Write-Host "Merge stopped on conflicts:" -ForegroundColor Yellow
                $conflicts | ForEach-Object { Write-Host "    $_" }
                Write-Host "Resolve them and commit, then re-run — or: git merge --abort"
                exit 1
            }
            Invoke-Git push origin $branch
            Write-Host "    merged and pushed"
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
        $lockMoved = @(& git -C $repo diff --name-only $script:beforeMerge HEAD -- pnpm-lock.yaml)
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
        Invoke-Step "Installing the freshly built CLI" {
            Install-TrellisCli -Repo $repo
        }
    }

    if (-not $SkipTests) {
        Invoke-Step "Running the PI-Desktop tests" {
            Push-Location (Join-Path $repo "packages/cli")
            try {
                $python = Resolve-TrellisPython
                if ($python) {
                    Write-Host "    PYTHON_CMD=$python"
                } else {
                    Write-Host "    no real python interpreter found; registry-invariants may fail" -ForegroundColor Yellow
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
    if (-not $SkipInstall) {
        Write-Host ("    trellis --version: {0}" -f (Get-TrellisVersion))
    }
    Write-Host "    publish a release: pwsh ./scripts/publish-fork.ps1"
} finally {
    Pop-Location
}
