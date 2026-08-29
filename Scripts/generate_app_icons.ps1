param(
    [string]$MasterPath = "Design/QuotaGlanceIconMaster.png",
    [string]$WatchBackgroundColor = "#315F91"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$resolvedMaster = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $MasterPath))
if (-not (Test-Path -LiteralPath $resolvedMaster -PathType Leaf)) {
    throw "Icon master not found: $resolvedMaster"
}

Add-Type -AssemblyName System.Drawing

function Convert-HexColor {
    param([string]$Value)

    if ($Value -notmatch '^#[0-9A-Fa-f]{6}$') {
        throw "Watch background color must use #RRGGBB: $Value"
    }
    return [System.Drawing.ColorTranslator]::FromHtml($Value)
}

function New-WatchIconSource {
    param(
        [System.Drawing.Image]$Source,
        [System.Drawing.Color]$TargetColor
    )

    $bitmap = [System.Drawing.Bitmap]::new(
        $Source.Width,
        $Source.Height,
        [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
    )
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.DrawImage($Source, 0, 0, $Source.Width, $Source.Height)
    } finally {
        $graphics.Dispose()
    }

    $bounds = [System.Drawing.Rectangle]::new(0, 0, $bitmap.Width, $bitmap.Height)
    $bits = $bitmap.LockBits(
        $bounds,
        [System.Drawing.Imaging.ImageLockMode]::ReadWrite,
        [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
    )
    try {
        $length = [Math]::Abs($bits.Stride) * $bitmap.Height
        $pixels = [byte[]]::new($length)
        [System.Runtime.InteropServices.Marshal]::Copy($bits.Scan0, $pixels, 0, $length)
        $blend = 0.82
        for ($y = 0; $y -lt $bitmap.Height; $y++) {
            $row = $y * $bits.Stride
            for ($x = 0; $x -lt $bitmap.Width; $x++) {
                $offset = $row + ($x * 3)
                $blue = $pixels[$offset]
                $green = $pixels[$offset + 1]
                $red = $pixels[$offset + 2]
                if ($red -lt 32 -and $green -lt 42 -and $blue -lt 60) {
                    $pixels[$offset] = [byte][Math]::Round($blue * (1 - $blend) + $TargetColor.B * $blend)
                    $pixels[$offset + 1] = [byte][Math]::Round($green * (1 - $blend) + $TargetColor.G * $blend)
                    $pixels[$offset + 2] = [byte][Math]::Round($red * (1 - $blend) + $TargetColor.R * $blend)
                }
            }
        }
        [System.Runtime.InteropServices.Marshal]::Copy($pixels, 0, $bits.Scan0, $length)
    } finally {
        $bitmap.UnlockBits($bits)
    }
    return $bitmap
}

function Write-RgbSquarePng {
    param(
        [System.Drawing.Image]$Source,
        [int]$PixelSize,
        [string]$OutputPath
    )

    $targetPath = [System.IO.Path]::GetFullPath($OutputPath)
    if (-not $targetPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to write outside repository: $targetPath"
    }

    $bitmap = [System.Drawing.Bitmap]::new(
        $PixelSize,
        $PixelSize,
        [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
    )
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.DrawImage($Source, 0, 0, $PixelSize, $PixelSize)
        } finally {
            $graphics.Dispose()
        }
        $bitmap.Save($targetPath, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $bitmap.Dispose()
    }
}

function Write-CatalogImages {
    param(
        [System.Drawing.Image]$Source,
        [string]$CatalogDirectory
    )

    $contentsPath = Join-Path $CatalogDirectory "Contents.json"
    $contents = Get-Content -LiteralPath $contentsPath -Raw | ConvertFrom-Json
    foreach ($entry in $contents.images) {
        if ([string]::IsNullOrWhiteSpace($entry.filename)) { continue }

        $pointSize = [double]::Parse(
            ($entry.size -split "x")[0],
            [System.Globalization.CultureInfo]::InvariantCulture
        )
        $scaleProperty = $entry.PSObject.Properties["scale"]
        $scale = if ($null -ne $scaleProperty -and $scaleProperty.Value) {
            [int](($scaleProperty.Value -replace "x", ""))
        } else {
            1
        }
        $pixelSize = [int][Math]::Round($pointSize * $scale)
        Write-RgbSquarePng -Source $Source -PixelSize $pixelSize -OutputPath (Join-Path $CatalogDirectory $entry.filename)
    }
}

$master = [System.Drawing.Image]::FromFile($resolvedMaster)
try {
    if ($master.Width -ne $master.Height) {
        throw "Icon master must be square; received $($master.Width)x$($master.Height)."
    }

    Write-CatalogImages -Source $master -CatalogDirectory (
        Join-Path $repoRoot "QuotaGlanceApp/Resources/Assets.xcassets/AppIcon.appiconset"
    )
    $watchMaster = New-WatchIconSource -Source $master -TargetColor (
        Convert-HexColor -Value $WatchBackgroundColor
    )
    try {
        Write-CatalogImages -Source $watchMaster -CatalogDirectory (
            Join-Path $repoRoot "QuotaGlanceWatch/Resources/Assets.xcassets/AppIcon.appiconset"
        )
    } finally {
        $watchMaster.Dispose()
    }
    foreach ($brandSize in @(128, 256, 384)) {
        Write-RgbSquarePng -Source $master -PixelSize $brandSize -OutputPath (
            Join-Path $repoRoot "SharedUI/Resources/QuotaGlanceBrand.xcassets/QuotaGlanceBrandIcon.imageset/QuotaGlanceBrandIcon-$brandSize.png"
        )
    }

    $obsoleteBrandPath = [System.IO.Path]::GetFullPath((
        Join-Path $repoRoot "SharedUI/Resources/QuotaGlanceBrand.xcassets/QuotaGlanceBrandIcon.imageset/QuotaGlanceBrandIcon-1024.png"
    ))
    if (-not $obsoleteBrandPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove outside repository: $obsoleteBrandPath"
    }
    if (Test-Path -LiteralPath $obsoleteBrandPath) {
        Remove-Item -LiteralPath $obsoleteBrandPath
    }
} finally {
    $master.Dispose()
}

Write-Output "Generated RGB AppIcon and shared brand assets from $resolvedMaster"
Write-Output "Applied Watch-only lighter background $WatchBackgroundColor"
