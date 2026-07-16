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
        [System.Drawing.Color]::FromArgb(228, 66, 66),
        [System.Drawing.Color]::FromArgb(242, 106, 61)
    )
    $Graphics.FillPath($BackgroundBrush, $BackgroundPath)

    $PanelPath = New-RoundedRectanglePath (19 * $Unit) (22 * $Unit) (90 * $Unit) (64 * $Unit) (17 * $Unit)
    $PanelBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 255))
    $Graphics.FillPath($PanelBrush, $PanelPath)

    $PlayBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(209, 55, 55))
    $Play = @(
        [System.Drawing.PointF]::new(45 * $Unit, 38 * $Unit),
        [System.Drawing.PointF]::new(45 * $Unit, 71 * $Unit),
        [System.Drawing.PointF]::new(75 * $Unit, 54.5 * $Unit)
    )
    $Graphics.FillPolygon($PlayBrush, $Play)

    $LineBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(245, 248, 255))
    $LineOne = New-RoundedRectanglePath (28 * $Unit) (96 * $Unit) (72 * $Unit) (8 * $Unit) (4 * $Unit)
    $LineTwo = New-RoundedRectanglePath (28 * $Unit) (109 * $Unit) (52 * $Unit) (8 * $Unit) (4 * $Unit)
    $Graphics.FillPath($LineBrush, $LineOne)
    $Graphics.FillPath($LineBrush, $LineTwo)

    $Output = New-Object System.Drawing.Bitmap $Size, $Size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $OutputGraphics = [System.Drawing.Graphics]::FromImage($Output)
    $OutputGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $OutputGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $OutputGraphics.DrawImage($Bitmap, 0, 0, $Size, $Size)
    $Output.Save((Join-Path $IconDir "icon$Size.png"), [System.Drawing.Imaging.ImageFormat]::Png)

    $OutputGraphics.Dispose()
    $Output.Dispose()
    $LineTwo.Dispose()
    $LineOne.Dispose()
    $LineBrush.Dispose()
    $PlayBrush.Dispose()
    $PanelBrush.Dispose()
    $PanelPath.Dispose()
    $BackgroundBrush.Dispose()
    $BackgroundPath.Dispose()
    $Graphics.Dispose()
    $Bitmap.Dispose()
}

Write-Host "Generated YouTube video-transcript icons in $IconDir"
