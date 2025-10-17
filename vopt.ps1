param (
    [string]$i,                        # Input directory
    [string]$o,                        # Output directory
    [switch]$skipOrienCheck,           # Skip orientation metadata check
    [switch]$help                      # Show usage/help
)

function Show-Usage {
    Write-Host "Usage:"
    Write-Host "  vopt -i <InputDirectory> [-o <OutputDirectory>] [-skipOrienCheck] [-help]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -i <InputDirectory>       Input folder containing videos (required)"
    Write-Host "  -o <OutputDirectory>      Output folder (default: <InputDirectory>\comp)"
    Write-Host "  -skipOrienCheck           Skip checking orientation/rotation metadata"
    Write-Host "  -help                     Show this help message"
    exit 0
}

# Show help if requested or no input
if ($help -or -not $i) {
    Show-Usage
}

# Normalize paths to absolute
try {
    $InputDir = (Resolve-Path -LiteralPath $i).Path
}
catch {
    Write-Error "❌ Input directory not found: $i"
    exit 1
}

if ($o) {
    try {
        $OutputDir = (Resolve-Path -LiteralPath $o).Path
    }
    catch {
        # If output dir does not exist yet, create it later
        $OutputDir = $o
    }
}
else {
    $OutputDir = Join-Path $InputDir "comp"
}

# Ensure output directory exists
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
    Write-Host "📁 Created output directory: $OutputDir"
}

# File to track processed videos
$voptFile = Join-Path $InputDir ".vopt"
$processedFiles = @()
if (Test-Path $voptFile) {
    $processedFiles = Get-Content $voptFile
}

# Supported video extensions
$extensions = '.mp4', '.mov', '.mts', '.mkv', '.avi', '.m4v', '.mpeg', '.mpg', '.wmv',
'.webm', '.flv', '.3gp', '.ts', '.vob', '.rm', '.rmvb', '.m2ts', '.f4v', '.asf'

# Collect video files
$videoFiles = Get-ChildItem -Path $InputDir -File | Where-Object { $extensions -contains $_.Extension.ToLower() }
$totalFiles = $videoFiles.Count
$currentIndex = 0

foreach ($file in $videoFiles) {
    $currentIndex++

    if ($processedFiles -contains $file.FullName) {
        Write-Host "⏭️  Skipping already processed: $($file.Name)"
        continue
    }

    $inFile = $file.FullName
    $name = $file.BaseName
    $outFile = Join-Path $OutputDir "$name.mp4"

    Write-Host "`n⏳ Processing $($currentIndex) of $($totalFiles): $($file.Name)"

    # Resolution + bitrate
    $resInfo = ffprobe -v error -select_streams v:0 -show_entries stream="width,height,bit_rate" -of csv=p=0 "$inFile"
    $resParts = $resInfo -split ',' | ForEach-Object { $_.Trim() }

    if ($resParts.Count -lt 2) {
        Write-Host "⚠️ Skipping (could not parse resolution): $($file.Name)"
        continue
    }

    $width = [int]$resParts[0]
    $height = [int]$resParts[1]

    $bitrate = 0
    if ($resParts.Count -gt 2 -and $resParts[2] -match '^\d+$') {
        $bitrate = [int]$resParts[2]
    }
    else {
        $formatBitrate = ffprobe -v error -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 "$inFile"
        if ($formatBitrate -match '^\d+$') {
            $bitrate = [int]$formatBitrate
        }
        else {
            Write-Host "⚠️ Could not determine bitrate, assuming 0: $($file.Name)"
            $bitrate = 0
        }
    }

    # Duration
    $durationOutput = ffprobe -v error -select_streams v:0 -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$inFile"
    $durationSeconds = if ($durationOutput -match '^\d+(\.\d+)?$') { [double]$durationOutput } else { 0 }

    # Orientation check
    $rotation = 'none'
    $extLower = $file.Extension.ToLower()

    if (-not $skipOrienCheck) {
        if ($durationSeconds -le 300 -or $extLower -eq '.mov') {
            $rotationOutput = ffprobe -v error -select_streams v:0 -show_entries side_data=rotation -of default=noprint_wrappers=1:nokey=1 "$inFile"
            $rotation = if ($rotationOutput) { ($rotationOutput -split '\s+')[0].Trim() } else { '' }
        }
    }

    if ($rotation -eq '90' -or $rotation -eq '270' -or $rotation -eq '-90') {
        $trueWidth = $height
        $trueHeight = $width
    }
    else {
        $trueWidth = $width
        $trueHeight = $height
    }

    $orientation = if ($trueWidth -gt $trueHeight) { 'landscape' } elseif ($trueHeight -gt $trueWidth) { 'portrait' } else { 'square' }
    if (-not $skipOrienCheck) {
        Write-Host "🧭 Detected orientation: $orientation (rotation: $($rotation -ne '' ? $rotation : 'none'))"
    }

    # Resize/bitrate logic
    $newWidth = $trueWidth
    $newHeight = $trueHeight
    $needsResize = $false
    $needsBitrateChange = $bitrate -gt 10000000

    switch ($orientation) {
        'landscape' {
            if ($trueWidth -gt 1920) {
                $newWidth = 1920
                $newHeight = [math]::Round($trueHeight * ($newWidth / $trueWidth))
                $needsResize = $true
            }
        }
        'portrait' {
            if ($trueHeight -gt 1920) {
                $newHeight = 1920
                $newWidth = [math]::Round($trueWidth * ($newHeight / $trueHeight))
                $needsResize = $true
            }
        }
        'square' {
            if ($trueWidth -gt 1080) {
                $newWidth = 1080
                $newHeight = 1080
                $needsResize = $true
            }
        }
    }

    if (-not $needsResize -and -not $needsBitrateChange) {
        Write-Host "🟡 Skipping: $($file.Name) (no resize ($($trueWidth)x$($trueHeight)) or bitrate ($($bitrate)) change needed), copying anyway!"
        Copy-Item $inFile $outFile
        Add-Content -Path $voptFile -Value $file.FullName
        continue
    }

    if ($needsResize) {
        Write-Host "🔄 Resizing: $($file.Name) → $newWidth x $newHeight @ 10 Mbps"
        ffmpeg -hide_banner -loglevel error -stats -y -i "$inFile" -vf "scale=$($newWidth):$($newHeight)" -b:v 10M -c:a copy "$outFile"
    }
    elseif ($needsBitrateChange) {
        Write-Host "📉 Reducing bitrate: $($file.Name) → 10 Mbps (no resize)"
        ffmpeg -hide_banner -loglevel error -stats -y -i "$inFile" -b:v 10M -c:a copy "$outFile"
    }

    Write-Host "✅ Done: $($file.Name)"
    Add-Content -Path $voptFile -Value $file.FullName
}

# Summary
function Get-DirSize([string]$path, [string[]]$filterExt, [string[]]$excludeFolders) {
    Get-ChildItem -Path $path -Recurse -File | Where-Object {
        $filterExt -contains $_.Extension.ToLower() -and
        ($excludeFolders -notcontains $_.Directory.Name)
    } | Measure-Object -Property Length -Sum | Select-Object -ExpandProperty Sum
}

$exclude = @("comp")
$srcSize = Get-DirSize $InputDir $extensions $exclude
$dstSize = Get-DirSize $OutputDir $extensions @()

$srcSizeMB = [math]::Round($srcSize / 1MB, 2)
$dstSizeMB = [math]::Round($dstSize / 1MB, 2)
$savedMB = [math]::Round(($srcSize - $dstSize) / 1MB, 2)
$savedPercent = if ($srcSize -gt 0) { [math]::Round((($srcSize - $dstSize) / $srcSize) * 100, 1) } else { 0 }

Write-Host "`n📊 Optimization Summary:"
Write-Host "📦 Source size: $srcSizeMB MB"
Write-Host "🎯 Output size: $dstSizeMB MB"
Write-Host "💾 Space saved: $savedMB MB ($savedPercent%)"