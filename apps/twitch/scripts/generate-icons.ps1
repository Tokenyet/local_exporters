$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$IconDir = Join-Path $Root "icons"

New-Item -ItemType Directory -Force -Path $IconDir | Out-Null
Add-Type -AssemblyName System.Drawing

function New-RoundedRectanglePath {
    param(
        [float]$X,
        [float]$Y,
        [float]$Width,
        [float]$Height,
        [float]$Radius
    )

    $Path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $Diameter = $Radius * 2
    $Path.AddArc($X, $Y, $Diameter, $Diameter, 180, 90)
    $Path.AddArc($X + $Width - $Diameter, $Y, $Diameter, $Diameter, 270, 90)
    $Path.AddArc($X + $Width - $Diameter, $Y + $Height - $Diameter, $Diameter, $Diameter, 0, 90)
    $Path.AddArc($X, $Y + $Height - $Diameter, $Diameter, $Diameter, 90, 90)
    $Path.CloseFigure()
    return $Path
}

foreach ($Size in @(16, 32, 48, 128)) {
    $Scale = 4
    $CanvasSize = $Size * $Scale
    $Unit = $CanvasSize / 128.0
    $Bitmap = New-Object System.Drawing.Bitmap $CanvasSize, $CanvasSize, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
    $Graphics.Clear([System.Drawing.Color]::Transparent)
    $Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $Graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    $BackgroundPath = New-RoundedRectanglePath (2 * $Unit) (2 * $Unit) (124 * $Unit) (124 * $Unit) (26 * $Unit)
    $BackgroundBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        [System.Drawing.PointF]::new(4 * $Unit, 4 * $Unit),
        [System.Drawing.PointF]::new(124 * $Unit, 124 * $Unit),
        [System.Drawing.Color]::FromArgb(116, 65, 215),
        [System.Drawing.Color]::FromArgb(65, 35, 123)
    )
    $Graphics.FillPath($BackgroundBrush, $BackgroundPath)

    $BubbleBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 255))
    $Tail = @(
        [System.Drawing.PointF]::new(37 * $Unit, 86 * $Unit),
        [System.Drawing.PointF]::new(37 * $Unit, 108 * $Unit),
        [System.Drawing.PointF]::new(59 * $Unit, 89 * $Unit)
    )
    $Graphics.FillPolygon($BubbleBrush, $Tail)
    $BubblePath = New-RoundedRectanglePath (20 * $Unit) (22 * $Unit) (88 * $Unit) (70 * $Unit) (17 * $Unit)
    $Graphics.FillPath($BubbleBrush, $BubblePath)

    $BarColors = @(
        [System.Drawing.Color]::FromArgb(75, 35, 143),
        [System.Drawing.Color]::FromArgb(16, 132, 122),
        [System.Drawing.Color]::FromArgb(236, 138, 24),
        [System.Drawing.Color]::FromArgb(75, 35, 143)
    )
    $Bars = @(
        @{ X = 38; Y = 53; H = 24 },
        @{ X = 51; Y = 44; H = 42 },
        @{ X = 64; Y = 37; H = 54 },
        @{ X = 77; Y = 49; H = 30 }
    )

    for ($Index = 0; $Index -lt $Bars.Count; $Index++) {
        $Bar = $Bars[$Index]
        $BarPath = New-RoundedRectanglePath ($Bar.X * $Unit) ($Bar.Y * $Unit) (8 * $Unit) ($Bar.H * $Unit) (4 * $Unit)
        $BarBrush = New-Object System.Drawing.SolidBrush $BarColors[$Index]
        $Graphics.FillPath($BarBrush, $BarPath)
        $BarBrush.Dispose()
        $BarPath.Dispose()
    }

    $Output = New-Object System.Drawing.Bitmap $Size, $Size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $OutputGraphics = [System.Drawing.Graphics]::FromImage($Output)
    $OutputGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $OutputGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $OutputGraphics.DrawImage($Bitmap, 0, 0, $Size, $Size)
    $Output.Save((Join-Path $IconDir "icon$Size.png"), [System.Drawing.Imaging.ImageFormat]::Png)

    $OutputGraphics.Dispose()
    $Output.Dispose()
    $BubblePath.Dispose()
    $BubbleBrush.Dispose()
    $BackgroundBrush.Dispose()
    $BackgroundPath.Dispose()
    $Graphics.Dispose()
    $Bitmap.Dispose()
}

Write-Host "Generated Twitch conversation-wave icons in $IconDir"
