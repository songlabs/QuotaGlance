param(
    [string]$MasterPath = "Design/QuotaGlanceIconMaster.png"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$resolvedMaster = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $MasterPath))
if (-not (Test-Path -LiteralPath $resolvedMaster -PathType Leaf)) {
    throw "Icon master not found: $resolvedMaster"
}

Add-Type -AssemblyName System.Drawing

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
    Write-CatalogImages -Source $master -CatalogDirectory (
        Join-Path $repoRoot "QuotaGlanceWatch/Resources/Assets.xcassets/AppIcon.appiconset"
    )
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
