param (
    [Parameter(Position = 0)]
    [string]$i,                        # Input directory (defaults to current directory if omitted)
    [Parameter(Position = 1)]
    [string]$o,                        # Output directory (defaults to <InputDirectory>\comp)
    [int]$quality = 85,                # Compression quality for JPEG/WebP (1-100, default: 85)
    [switch]$skipOrienCheck,           # Skip orientation check
    [switch]$help                      # Show usage/help
)

function Show-Usage {
    Write-Host "Usage:"
    Write-Host "  iopt [[-i] <InputDirectory>] [[-o] <OutputDirectory>] [-quality <1-100>] [-skipOrienCheck] [-help]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -i <InputDirectory>       Input folder containing images (default: current directory)"
    Write-Host "  -o <OutputDirectory>      Output folder (default: <InputDirectory>\comp)"
    Write-Host "  -quality <1-100>          Image compression quality (default: 85)"
    Write-Host "  -skipOrienCheck           Skip checking and fixing EXIF orientation/rotation"
    Write-Host "  -help                     Show this help message"
    exit 0
}

# Show help if requested
if ($help) {
    Show-Usage
}

# Verify ImageMagick is available
if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
    Write-Error "[ERROR] ImageMagick ('magick') command was not found in PATH."
    exit 1
}

# Default input directory to current working directory if not specified
if (-not $i) {
    $i = (Get-Location).Path
}

# Normalize input path to absolute
try {
    $InputDir = (Resolve-Path -LiteralPath $i).Path
}
catch {
    Write-Error "[ERROR] Input directory not found: $i"
    exit 1
}

# Determine output directory
if ($o) {
    if (Test-Path -LiteralPath $o) {
        $OutputDir = (Resolve-Path -LiteralPath $o).Path
    }
    else {
        $OutputDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($o)
    }
}
else {
    $OutputDir = Join-Path $InputDir "comp"
}

# Ensure output directory exists (create it if not present)
if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    Write-Host "[DIR] Created output directory: $OutputDir"
}

# Resolve paths to canonical forms for safety comparison
$resolvedInput  = (Resolve-Path -LiteralPath $InputDir).Path
$resolvedOutput = (Resolve-Path -LiteralPath $OutputDir).Path

# ---- SAFETY CHECK: Input and Output must not be the same ----
if ($resolvedInput.TrimEnd('\', '/') -ieq $resolvedOutput.TrimEnd('\', '/')) {
    Write-Error "[ERROR] Input and Output directories resolve to the SAME path. This is not allowed."
    Write-Error "        Input : $resolvedInput"
    Write-Error "        Output: $resolvedOutput"
    exit 1
}

# File to track processed images
$ioptFile = Join-Path $InputDir ".iopt"
$processedFiles = @()
if (Test-Path $ioptFile) {
    $processedFiles = Get-Content $ioptFile
}

# Supported image extensions
$extensions = '.jpg', '.jpeg', '.png', '.webp', '.tiff', '.tif', '.bmp', '.heic', '.avif'

# Collect image files
$imageFiles = Get-ChildItem -Path $InputDir -File | Where-Object { $extensions -contains $_.Extension.ToLower() }
$totalFiles = $imageFiles.Count
$currentIndex = 0

Write-Host "Found $totalFiles image(s) to inspect in: $InputDir"

foreach ($file in $imageFiles) {
    $currentIndex++

    if ($processedFiles -contains $file.FullName) {
        Write-Host "[SKIP] Already processed: $($file.Name)"
        continue
    }

    $inFile  = $file.FullName
    $outFile = Join-Path $OutputDir $file.Name

    Write-Host "`n[$currentIndex/$totalFiles] Inspecting: $($file.Name)"

    # Identify image dimensions and orientation tag
    $identOutput = magick identify -format "%w,%h,%[orientation]" "$inFile" 2>$null
    if (-not $identOutput) {
        Write-Host "[WARN] Could not identify image properties, skipping: $($file.Name)"
        continue
    }

    $parts = ($identOutput -split ',') | ForEach-Object { $_.Trim() }
    if ($parts.Count -lt 2) {
        Write-Host "[WARN] Invalid geometry returned from identify, skipping: $($file.Name)"
        continue
    }

    $width = [int]$parts[0]
    $height = [int]$parts[1]
    $orientation = if ($parts.Count -ge 3 -and $parts[2]) { $parts[2] } else { 'Undefined' }

    # Check orientation fix requirement
    $needsOrientationFix = $false
    if (-not $skipOrienCheck) {
        if ($orientation -ne 'Undefined' -and $orientation -ne 'TopLeft' -and $orientation -ne '1') {
            $needsOrientationFix = $true
        }
    }

    # Dimensions check: fit-inside box 1920x1920
    $needsResize = ($width -gt 1920 -or $height -gt 1920)

    # If within 1920x1920 box and no rotation needed, copy directly to comp
    if (-not $needsResize -and -not $needsOrientationFix) {
        Write-Host "[COPY] Within limit (${width}x${height}, orientation: $orientation). Copying to comp..."
        Copy-Item -LiteralPath $inFile -Destination $outFile -Force
        Add-Content -Path $ioptFile -Value $file.FullName
        continue
    }

    # Perform optimization
    $actionMsg = @()
    if ($needsResize) { $actionMsg += "fit 1920x1920 box" }
    if ($needsOrientationFix) { $actionMsg += "auto-orient ($orientation)" }
    $actionDesc = $actionMsg -join ", "

    Write-Host "[OPTIMIZING] ($actionDesc) with quality $quality..."

    if ($skipOrienCheck) {
        magick "$inFile" -resize "1920x1920>" -quality $quality "$outFile"
    }
    else {
        magick "$inFile" -auto-orient -resize "1920x1920>" -quality $quality "$outFile"
    }

    if (Test-Path -LiteralPath $outFile) {
        $origSize = (Get-Item -LiteralPath $inFile).Length
        $optSize  = (Get-Item -LiteralPath $outFile).Length
        $diffKB   = [math]::Round(($origSize - $optSize) / 1KB, 1)

        Write-Host "[DONE] Saved: $($file.Name) (Size: $([math]::Round($origSize/1KB, 1)) KB -> $([math]::Round($optSize/1KB, 1)) KB, diff: $diffKB KB)"
        Add-Content -Path $ioptFile -Value $file.FullName
    }
    else {
        Write-Error "[ERROR] Failed to output optimized file: $outFile"
    }
}

# Retain .iopt file as a persistent record of completed conversions
if (Test-Path $ioptFile) {
    Write-Host "`n[RECORD] Conversion record preserved in: $ioptFile"
}

# Summary
function Get-DirSize([string]$path, [string[]]$filterExt, [string[]]$excludeFolders) {
    $matched = Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
        $filterExt -contains $_.Extension.ToLower() -and
        ($excludeFolders -notcontains $_.Directory.Name)
    }
    if ($matched) {
        ($matched | Measure-Object -Property Length -Sum).Sum
    }
    else {
        0
    }
}

$exclude = @("comp")
$srcSize = Get-DirSize $InputDir $extensions $exclude
$dstSize = Get-DirSize $OutputDir $extensions @()

$srcSizeMB = [math]::Round($srcSize / 1MB, 2)
$dstSizeMB = [math]::Round($dstSize / 1MB, 2)
$savedMB = [math]::Round(($srcSize - $dstSize) / 1MB, 2)
$savedPercent = if ($srcSize -gt 0) { [math]::Round((($srcSize - $dstSize) / $srcSize) * 100, 1) } else { 0 }

Write-Host "`n================ Optimization Summary ================"
Write-Host "Source directory size : $srcSizeMB MB"
Write-Host "Output directory size : $dstSizeMB MB"
Write-Host "Total space saved     : $savedMB MB ($savedPercent%)"
Write-Host "======================================================"
