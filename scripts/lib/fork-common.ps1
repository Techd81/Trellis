# Shared helpers for the fork scripts. Dot-source from a script at scripts/.
#
# Kept here so install-fork.ps1 and sync-upstream.ps1 agree on how the CLI is
# published and which Python the tests use.

<#
.SYNOPSIS
    Pack the CLI with pnpm and install the tarball as the global `trellis`.
.DESCRIPTION
    `pnpm pack` rewrites `workspace:*` to the real version, so the tarball is
    installable with npm; `@mindfoldhq/trellis-core` comes from the registry.
#>
function Install-TrellisCli {
    param([Parameter(Mandatory)][string]$Repo)

    $stage = Join-Path ([System.IO.Path]::GetTempPath()) ("trellis-fork-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    try {
        & pnpm --filter @mindfoldhq/trellis pack --pack-destination $stage
        if ($LASTEXITCODE -ne 0) { throw "pnpm pack failed" }
        $tgz = Get-ChildItem $stage -Filter *.tgz | Select-Object -First 1
        if (-not $tgz) { throw "no tarball was produced" }
        & npm install -g --force $tgz.FullName
        if ($LASTEXITCODE -ne 0) { throw "npm install -g failed" }
        Write-Host "    installed $($tgz.Name)"
    } finally {
        Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
    }
}

<#
.SYNOPSIS
    Point PYTHON_CMD at a real interpreter when the caller has not chosen one.
.DESCRIPTION
    registry-invariants shells out to `python3`, which resolves to a Microsoft
    Store stub on a stock Windows install. Returns the chosen command, or an
    empty string when nothing usable was found.
#>
function Resolve-TrellisPython {
    if ($env:PYTHON_CMD) { return $env:PYTHON_CMD }
    foreach ($candidate in @("python", "py", "python3")) {
        $found = Get-Command $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found -and $found.Source -notmatch "WindowsApps") {
            $env:PYTHON_CMD = $found.Source
            return $env:PYTHON_CMD
        }
    }
    return ""
}

<#
.SYNOPSIS
    The version the installed `trellis` reports, ignoring its update banner.
#>
function Get-TrellisVersion {
    return (@(& trellis --version 2>&1) |
        Where-Object { $_ -match '^\d+\.\d+\.\d+' } |
        Select-Object -Last 1)
}
