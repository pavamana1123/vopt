param (
    [Parameter(Position = 0)]
    [string]$i,                        # Input directory (defaults to current directory if omitted)
    [Parameter(Position = 1)]
    [string]$o,                        # Base output directory (defaults to input directory if omitted)
    [int]$quality = 85,                # Compression quality for images (1-100, default: 85)
    [switch]$skipOrienCheck,           # Skip orientation check for images and videos
    [switch]$help                      # Show usage/help
)

function Show-Usage {
    Write-Host "Usage:"
    Write-Host "  opt [[-i] <InputDirectory>] [[-o] <BaseOutputDirectory>] [-quality <1-100>] [-skipOrienCheck] [-help]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -i <InputDirectory>         Input folder containing media (default: current directory)"
    Write-Host "  -o <BaseOutputDirectory>    Base output folder for 'img' and 'vid' (default: <InputDirectory>)"
    Write-Host "  -quality <1-100>            Compression quality for images (default: 85)"
    Write-Host "  -skipOrienCheck             Skip checking orientation metadata"
    Write-Host "  -help                       Show this help message"
    Write-Host ""
    Write-Host "Behavior:"
    Write-Host "  Creates 'img' and 'vid' folders, then runs 'iopt' on images and 'vopt' on videos."
    exit 0
}

# Show help if requested
if ($help) {
    Show-Usage
}

$ioptScript = Join-Path $PSScriptRoot "iopt.ps1"
$voptScript = Join-Path $PSScriptRoot "vopt.ps1"

if (-not (Test-Path -LiteralPath $ioptScript)) {
    Write-Error "[ERROR] iopt.ps1 not found at: $ioptScript"
    exit 1
}

if (-not (Test-Path -LiteralPath $voptScript)) {
    Write-Error "[ERROR] vopt.ps1 not found at: $voptScript"
    exit 1
}

# Default input directory to current working directory if not specified
if (-not $i) {
    $i = (Get-Location).Path
}

# Normalize input path
try {
    $InputDir = (Resolve-Path -LiteralPath $i).Path
}
catch {
    Write-Error "[ERROR] Input directory not found: $i"
    exit 1
}

# Determine base output directory
if ($o) {
    if (Test-Path -LiteralPath $o) {
        $BaseOutputDir = (Resolve-Path -LiteralPath $o).Path
    }
    else {
        $BaseOutputDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($o)
    }
}
else {
    $BaseOutputDir = $InputDir
}

# Define target image and video folders
$imgDir = Join-Path $BaseOutputDir "img"
$vidDir = Join-Path $BaseOutputDir "vid"

# Ensure target directories exist
if (-not (Test-Path -LiteralPath $imgDir)) {
    New-Item -ItemType Directory -Path $imgDir -Force | Out-Null
    Write-Host "[DIR] Created images output directory: $imgDir"
}

if (-not (Test-Path -LiteralPath $vidDir)) {
    New-Item -ItemType Directory -Path $vidDir -Force | Out-Null
    Write-Host "[DIR] Created videos output directory: $vidDir"
}

Write-Host "======================================================"
Write-Host "[OPT] Starting Optimization"
Write-Host "Source directory : $InputDir"
Write-Host "Images directory : $imgDir"
Write-Host "Videos directory : $vidDir"
Write-Host "======================================================"

# 1. Run iopt for images
Write-Host "`n[PHASE 1] Optimizing Images..."
$ioptParams = @{
    i = $InputDir
    o = $imgDir
    quality = $quality
}
if ($skipOrienCheck) {
    $ioptParams["skipOrienCheck"] = $true
}
& $ioptScript @ioptParams

# 2. Run vopt for videos
Write-Host "`n[PHASE 2] Optimizing Videos..."
$voptParams = @{
    i = $InputDir
    o = $vidDir
}
if ($skipOrienCheck) {
    $voptParams["skipOrienCheck"] = $true
}
& $voptScript @voptParams

Write-Host "`n======================================================"
Write-Host "[OPT] Complete: All images and videos optimized."
Write-Host "Images saved to : $imgDir"
Write-Host "Videos saved to : $vidDir"
Write-Host "======================================================"
