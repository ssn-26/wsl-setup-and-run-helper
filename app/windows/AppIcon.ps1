# ==============================================================================
# WSL Control Panel - the app icon: a terminal window drawn in white on the
# Windows accent colour. Used by the window (title bar, taskbar) and by
# install.ps1, which saves it as the .ico of the launcher and the shortcuts.
#
# Keep this file plain ASCII (Windows PowerShell 5.1 reads it as ANSI).
# ==============================================================================

Add-Type -AssemblyName PresentationCore, WindowsBase

# The accent colour chosen in Windows (stored as ABGR), as '#RRGGBB'.
function Get-WindowsAccent {
    try {
        $v = [int64](Get-ItemPropertyValue -Path 'HKCU:\Software\Microsoft\Windows\DWM' -Name AccentColor -ErrorAction Stop) -band 0xFFFFFFFF
        return ('#{0:X2}{1:X2}{2:X2}' -f ($v -band 0xFF), (($v -shr 8) -band 0xFF), (($v -shr 16) -band 0xFF))
    } catch { return '#0078D4' }
}

# The icon as a $size x $size bitmap on the colour $hex ('#RRGGBB'). Drawn on a
# 64-unit grid; small sizes get a slightly thicker line so it stays readable.
function New-AppIconBitmap([int]$size = 64, [string]$hex = '#0078D4') {
    $conv = New-Object Windows.Media.BrushConverter
    $dv = New-Object Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    $dc.PushTransform((New-Object Windows.Media.ScaleTransform ($size / 64.0), ($size / 64.0)))
    $dc.DrawRoundedRectangle([Windows.Media.Brush]$conv.ConvertFromString($hex), $null, (New-Object Windows.Rect 0, 0, 64, 64), 14, 14)
    $pen = New-Object Windows.Media.Pen ([Windows.Media.Brushes]::White), ([math]::Max(5, 96.0 / $size))
    $pen.StartLineCap = 'Round'; $pen.EndLineCap = 'Round'; $pen.LineJoin = 'Round'
    $dc.DrawRoundedRectangle($null, $pen, (New-Object Windows.Rect 12, 14, 40, 36), 6, 6)
    $dc.DrawGeometry($null, $pen, [Windows.Media.Geometry]::Parse('M 21,26 L 28,32 L 21,38'))
    $dc.DrawLine($pen, (New-Object Windows.Point 32, 38), (New-Object Windows.Point 42, 38))
    $dc.Pop()
    $dc.Close()
    $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap $size, $size, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($dv)
    $bmp.Freeze()
    return $bmp
}

# Writes a Windows .ico with the usual sizes (PNG-compressed entries, which
# Windows Vista and later read).
function Save-AppIco([string]$path, [string]$hex = '#0078D4') {
    $sizes = @(16, 20, 24, 32, 40, 48, 64, 256)
    $pngs = New-Object 'System.Collections.Generic.List[byte[]]'
    foreach ($s in $sizes) {
        $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create((New-AppIconBitmap $s $hex)))
        $ms = New-Object IO.MemoryStream
        $enc.Save($ms)
        $pngs.Add($ms.ToArray())
        $ms.Dispose()
    }
    $fs = [IO.File]::Create($path)
    $w = New-Object IO.BinaryWriter $fs
    try {
        $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
        $offset = 6 + 16 * $sizes.Count
        for ($i = 0; $i -lt $sizes.Count; $i++) {
            $b = [byte]($sizes[$i] % 256)   # 256 is stored as 0
            $w.Write($b); $w.Write($b); $w.Write([byte]0); $w.Write([byte]0)
            $w.Write([uint16]1); $w.Write([uint16]32)
            $w.Write([uint32]$pngs[$i].Length); $w.Write([uint32]$offset)
            $offset += $pngs[$i].Length
        }
        foreach ($p in $pngs) { $w.Write($p) }
    } finally { $w.Close() }
}
