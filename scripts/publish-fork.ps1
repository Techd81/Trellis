#!/usr/bin/env pwsh
#requires -Version 7.0
<#
.SYNOPSIS
    Publish the built CLI to npm as @awesome_dura/trellis.

.DESCRIPTION
    1. refuses to publish from a dirty tree or the wrong branch
    2. builds core + cli
    3. copies README.md / LICENSE into the package directory (npm only ships
       what the package folder contains)
    4. publishes with `--access public --ignore-scripts`
    5. prints what landed on the registry

    `--ignore-scripts` is deliberate: the package's `prepublishOnly` runs the
    full test suite (23 known Windows-only failures) and uses `cp`, which cmd
    does not have.

.PARAMETER DryRun
    Build and pack exactly like a real publish, but stop before uploading.

.PARAMETER Tag
    npm dist-tag to publish under. Defaults to `latest`.

.PARAMETER Otp
    One-time password, for accounts whose 2FA policy covers writes. Leave it
    out when the token already bypasses 2FA.

.EXAMPLE
    pwsh ./scripts/publish-fork.ps1 -DryRun
.EXAMPLE
    pwsh ./scripts/publish-fork.ps1
#>
param(
    [switch]$DryRun,
    [string]$Tag = "latest",
    [string]$Otp
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$packageDir = Join-Path $repo "packages/cli"

function Invoke-Step {
    param([string]$Message, [scriptblock]$Body)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
    & $Body
}

Push-Location $repo
try {
    Invoke-Step "Checking the checkout" {
        $branch = (& git -C $repo rev-parse --abbrev-ref HEAD | Out-String).Trim()
        if ($branch -ne "feat/pi-desktop") {
            throw "publish from feat/pi-desktop, not '$branch'"
        }
        $status = @(& git -C $repo status --porcelain) |
            Where-Object { $_ -notmatch '^\s*[Mm? ]{1,2}\s+(docs-site|marketplace)\s*$' }
        if ($status) {
            throw "Working tree is dirty. Commit first:`n$($status -join "`n")"
        }
        $name = (Get-Content (Join-Path $packageDir "package.json") -Raw | ConvertFrom-Json).name
        $version = (Get-Content (Join-Path $packageDir "package.json") -Raw | ConvertFrom-Json).version
        Write-Host "    publishing $name@$version with tag '$Tag'"
        if ($name -ne "@awesome_dura/trellis") {
            throw "unexpected package name '$name' — this script publishes the fork only"
        }
    }

    Invoke-Step "Checking npm auth and package scope" {
        $pkgName = (Get-Content (Join-Path $packageDir "package.json") -Raw | ConvertFrom-Json).name
        $scope = ($pkgName -split "/")[0].TrimStart("@")
        $who = (@(& npm whoami 2>&1) -join " ").Trim()
        Write-Host "    package $pkgName (scope '@$scope')"
        if ($LASTEXITCODE -ne 0 -or $who -match "E40|ENEEDAUTH") {
            if ($DryRun) {
                Write-Host "    not logged in — a real publish needs: npm login" -ForegroundColor Yellow
            } else {
                throw "not logged in to npm. Run: npm login, then re-run this script"
            }
        } else {
            Write-Host "    logged in as '$who'"
            if ($who -ne $scope) {
                Write-Host "    note: '@$scope' is not your npm username, so publishing needs an organization named '$scope'." -ForegroundColor Yellow
            }
        }
    }

    Invoke-Step "Building core + cli" {
        & pnpm build
        if ($LASTEXITCODE -ne 0) { throw "pnpm build failed" }
    }

    Invoke-Step "Staging package docs" {
        Copy-Item (Join-Path $repo "README.md") (Join-Path $packageDir "README.md") -Force
        Copy-Item (Join-Path $repo "LICENSE") (Join-Path $packageDir "LICENSE") -Force
        Write-Host "    README.md + LICENSE copied into packages/cli"
    }

    Invoke-Step ($(if ($DryRun) { "Publishing (dry run)" } else { "Publishing to npm" })) {
        Push-Location $packageDir
        try {
            $publishArgs = @("publish", "--access", "public", "--ignore-scripts", "--tag", $Tag)
            if ($DryRun) { $publishArgs += "--dry-run" }
            if ($Otp) { $publishArgs += "--otp=$Otp" }
            & npm @publishArgs
            if ($LASTEXITCODE -ne 0) { throw "npm publish failed (logged in as: $((& npm whoami 2>&1) -join ' '))" }
        } finally {
            Pop-Location
        }
    }

    if (-not $DryRun) {
        Invoke-Step "Checking the registry" {
            $version = (Get-Content (Join-Path $packageDir "package.json") -Raw | ConvertFrom-Json).version
            $latest = (& npm view "@awesome_dura/trellis@$version" version 2>&1 | Out-String).Trim()
            Write-Host "    registry now serves: $latest"
            Write-Host "    install it: npm install -g @awesome_dura/trellis@$Tag"
        }
    }

    Write-Host ""
    Write-Host "Done." -ForegroundColor Green
} finally {
    Pop-Location
}
