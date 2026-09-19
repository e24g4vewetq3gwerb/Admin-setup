<#
.SYNOPSIS
  Two circular badges: folder and PowerShell. Whole circle is clickable.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$mutex = New-Object System.Threading.Mutex($false, 'Local\AdminSetupFolderLogo')
if (-not $mutex.WaitOne(0, $false)) { return }

$size = 58
$gap = 16
$pad = 2

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Launch'
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.ShowInTaskbar = $false
$form.TopMost = $true
$form.Size = New-Object System.Drawing.Size((($size * 2) + $gap + ($pad * 2)), ($size + ($pad * 2)))
$form.BackColor = [System.Drawing.Color]::Black

$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$path.AddEllipse($pad, $pad, $size, $size)
$path.AddEllipse(($pad + $size + $gap), $pad, $size, $size)
$form.Region = New-Object System.Drawing.Region($path)

function Move-ToBottom {
  $s = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $x = [int](($s.Width - $form.Width) / 2)
  $y = $s.Bottom - $form.Height - 12
  $form.Location = New-Object System.Drawing.Point($x, $y)
}
Move-ToBottom

function Get-AppIcon([string]$Exe, [int]$Px) {
  try {
    $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($Exe)
    if ($ico) { return $ico.ToBitmap() }
  } catch {}
  $bmp = New-Object System.Drawing.Bitmap $Px, $Px
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.Clear([System.Drawing.Color]::Transparent)
  $g.Dispose()
  return $bmp
}

$folderIcon = Get-AppIcon (Join-Path $env:SystemRoot 'explorer.exe') 32
$psIcon = Get-AppIcon (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') 32
$yellow = [System.Drawing.Color]::FromArgb(255, 196, 37)
$blue = [System.Drawing.Color]::FromArgb(55, 148, 230)
$fillA = [System.Drawing.Color]::FromArgb(36, 36, 36)
$fillB = [System.Drawing.Color]::FromArgb(22, 32, 48)

function Draw-Badge($g, [int]$x, [int]$y, $fill, $ring, $img) {
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $outer = New-Object System.Drawing.Rectangle($x, $y, $size, $size)
  $brush = New-Object System.Drawing.SolidBrush($fill)
  $g.FillEllipse($brush, $outer)
  $brush.Dispose()
  $pen = New-Object System.Drawing.Pen($ring, 3)
  $inset = New-Object System.Drawing.Rectangle(($x + 2), ($y + 2), ($size - 5), ($size - 5))
  $g.DrawEllipse($pen, $inset)
  $pen.Dispose()
  if ($img) {
    $iw = 28
    $ix = $x + [int](($size - $iw) / 2)
    $iy = $y + [int](($size - $iw) / 2)
    $g.DrawImage($img, $ix, $iy, $iw, $iw)
  }
}

$form.add_Paint({
  param($sender, $e)
  $e.Graphics.Clear([System.Drawing.Color]::Black)
  Draw-Badge $e.Graphics $pad $pad $fillA $yellow $folderIcon
  Draw-Badge $e.Graphics ($pad + $size + $gap) $pad $fillB $blue $psIcon
})

function Test-InCircle([int]$px, [int]$py, [int]$cx, [int]$cy) {
  $dx = $px - ($cx + ($size / 2))
  $dy = $py - ($cy + ($size / 2))
  return (($dx * $dx) + ($dy * $dy)) -le [Math]::Pow(($size / 2), 2)
}

function Open-Folder {
  $target = $env:USERPROFILE
  if (-not (Test-Path -LiteralPath $target)) { $target = $env:SystemDrive + '\' }
  Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList @("`"$target`"") | Out-Null
}
function Open-PowerShell {
  $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  Start-Process -FilePath $ps -WorkingDirectory $env:USERPROFILE | Out-Null
}

$form.add_MouseDown({
  param($sender, $e)
  if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
  if (Test-InCircle $e.X $e.Y $pad $pad) { Open-Folder; return }
  if (Test-InCircle $e.X $e.Y ($pad + $size + $gap) $pad) { Open-PowerShell }
})

$form.add_Shown({ Move-ToBottom; $form.Invalidate() })
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.add_Tick({ if (-not $form.IsDisposed) { Move-ToBottom; $form.TopMost = $true } })
$timer.Start()

[void][System.Windows.Forms.Application]::Run($form)
