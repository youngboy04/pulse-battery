# Original vector artwork, rasterized into the Windows application icon.
Add-Type -AssemblyName System.Drawing
$bitmap = New-Object Drawing.Bitmap 64,64
$g = [Drawing.Graphics]::FromImage($bitmap)
$g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([Drawing.Color]::Transparent)
$mintBrush = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(183,245,155))
$inkBrush = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(23,36,18))
$g.FillEllipse($mintBrush,2,2,60,60)
[Drawing.PointF[]]$bolt = @([Drawing.PointF]::new(35,10),[Drawing.PointF]::new(18,35),[Drawing.PointF]::new(29,35),[Drawing.PointF]::new(26,54),[Drawing.PointF]::new(47,27),[Drawing.PointF]::new(35,27))
$g.FillPolygon($inkBrush,$bolt)
$memory = New-Object IO.MemoryStream
$bitmap.Save($memory,[Drawing.Imaging.ImageFormat]::Png)
$png = $memory.ToArray()
$target = Join-Path (Split-Path $PSScriptRoot -Parent) 'windows\runner\resources\app_icon.ico'
$stream = [IO.File]::Create($target)
$writer = New-Object IO.BinaryWriter $stream
$writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]1)
$writer.Write([byte]64); $writer.Write([byte]64); $writer.Write([byte]0); $writer.Write([byte]0)
$writer.Write([uint16]1); $writer.Write([uint16]32); $writer.Write([uint32]$png.Length); $writer.Write([uint32]22)
$writer.Write($png)
$writer.Dispose(); $stream.Dispose(); $memory.Dispose(); $g.Dispose(); $bitmap.Dispose(); $mintBrush.Dispose(); $inkBrush.Dispose()
