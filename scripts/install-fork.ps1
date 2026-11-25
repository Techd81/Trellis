#!/usr/bin/env pwsh
#requires -Version 7.0
<#
.SYNOPSIS
    Build this fork and install it as the global `trellis` command.

.DESCRIPTION
    Run this from a clone of Techd81/Trellis sitting on the `feat/pi-desktop`
    branch. It installs dependencies, runs the PI-Desktop tests, builds core +
    cli, packs the CLI with pnpm (which rewrites `workspace:*` to real version
    numbers) and installs that tarball with npm.

    Vendoring the build into an existing upstream package is not needed: the
    packed tarball pulls `@mindfoldhq/trellis-core` from npm itself.

    Prefer `npm install -g @awesome_dura/trellis@latest` once that package is
    published; this script is the build-from-source path.

.PARAMETER SkipTests
    Skip the test run (faster, but you lose the check that the checkout is sane).

.EXAMPLE
    pwsh ./scripts/install-fork.ps1
.EXAMPLE
    pwsh ./scripts/install-fork.ps1 -SkipTests
#>
param(
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "lib/fork-common.ps1")

function Invoke-Step {
    param([string]$Message, [scriptblock]$Body)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
    & $Body
}

Push-Location $repo
try {
    Invoke-Step "Checking the toolchain" {
        foreach ($tool in @("node", "pnpm", "npm")) {
            if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
                throw "$tool is required but was not found on PATH"
            }
        }
        $branch = (& git -C $repo rev-parse --abbrev-ref HEAD | Out-String).Trim()
        if ($branch -ne "feat/pi-desktop") {
            Write-Host "    warning: on '$branch', not 'feat/pi-desktop' — the built CLI may lack PI-Desktop" -ForegroundColor Yellow
        } else {
            Write-Host "    branch: $branch"
        }
    }

    Invoke-Step "Installing dependencies" {
        & pnpm install
        if ($LASTEXITCODE -ne 0) { throw "pnpm install failed" }
    }

    if (-not $SkipTests) {
        Invoke-Step "Running the PI-Desktop tests" {
            $python = Resolve-TrellisPython
            if ($python) {
                Write-Host "    PYTHON_CMD=$python"
            } else {
                Write-Host "    no real python interpreter found; registry-invariants may fail" -ForegroundColor Yellow
            }
            Push-Location (Join-Path $repo "packages/cli")
            try {
                & npx vitest run --maxWorkers=3 test/commands/pi-desktop.test.ts test/templates/pi-desktop.test.ts test/registry-invariants.test.ts
                if ($LASTEXITCODE -ne 0) { throw "tests failed" }
            } finally {
                Pop-Location
            }
        }
    }

    Invoke-Step "Building core + cli" {
        & pnpm build
        if ($LASTEXITCODE -ne 0) { throw "pnpm build failed" }
    }

    Invoke-Step "Installing the CLI globally" {
        Install-TrellisCli -Repo $repo
    }

    Invoke-Step "Verifying" {
        Write-Host "    trellis --version: $(Get-TrellisVersion)"
        $help = @(& trellis init --help 2>&1)
        if (-not ($help -match '--pi-desktop')) {
            throw "the installed CLI does not expose --pi-desktop; is the checkout on feat/pi-desktop?"
        }
        Write-Host "    --pi-desktop: present" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "Done." -ForegroundColor Green
    Write-Host "    revert to the upstream package: npm install -g @mindfoldhq/trellis --force"
    Write-Host "    follow upstream later:          pwsh ./scripts/sync-upstream.ps1"
} finally {
    Pop-Location
}
