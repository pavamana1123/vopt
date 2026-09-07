<#
.SYNOPSIS
    Adds or updates the 'vopt' and 'iopt' command functions in the user's PowerShell profile ($PROFILE).
#>

$voptPath = Join-Path $PSScriptRoot "vopt.ps1"
$ioptPath = Join-Path $PSScriptRoot "iopt.ps1"

if (-not (Test-Path -LiteralPath $voptPath)) {
    Write-Error "[ERROR] Could not find vopt.ps1 at: $voptPath"
    exit 1
}

if (-not (Test-Path -LiteralPath $ioptPath)) {
    Write-Error "[ERROR] Could not find iopt.ps1 at: $ioptPath"
    exit 1
}

$profilePath = $PROFILE
$profileDir = Split-Path -Path $profilePath -Parent

# Ensure profile directory exists
if (-not (Test-Path -LiteralPath $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    Write-Host "[DIR] Created profile directory: $profileDir"
}

# Ensure profile file exists
if (-not (Test-Path -LiteralPath $profilePath)) {
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
    Write-Host "[FILE] Created profile file: $profilePath"
}

function Add-Or-Update-Command {
    param (
        [string]$CmdName,
        [string]$CmdScriptPath,
        [string]$FilePath
    )

    $def = @"

function $CmdName {
    & "$CmdScriptPath" @args
}
"@
    $content = Get-Content -Path $FilePath -Raw
    $pattern = "(?ms)(#\s*)?function\s+$CmdName\s*\{[^}]*\}"

    if ($content -match $pattern) {
        $newContent = $content -replace $pattern, $def.Trim()
        Set-Content -Path $FilePath -Value $newContent -NoNewline
        Write-Host "[UPDATED] Function '$CmdName' in: $FilePath"
    }
    else {
        Add-Content -Path $FilePath -Value $def
        Write-Host "[ADDED] Function '$CmdName' in: $FilePath"
    }
}

Add-Or-Update-Command -CmdName "vopt" -CmdScriptPath $voptPath -FilePath $profilePath
Add-Or-Update-Command -CmdName "iopt" -CmdScriptPath $ioptPath -FilePath $profilePath

Write-Host "`nTo start using 'vopt' and 'iopt' right away in your current session, run:"
Write-Host "  . `$PROFILE" -ForegroundColor Cyan
