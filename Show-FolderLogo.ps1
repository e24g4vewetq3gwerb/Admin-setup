<#
.SYNOPSIS
  Three circular badges: folder, PowerShell, rerun wipe script.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$mutex = New-Object System.Threading.Mutex($false, 'Local\AdminSetupFolderLogo')
if (-not $mutex.WaitOne(0, $false)) { return }

$size = 60
$gap = 18
$pad = 3
$count = 3
$magenta = [System.Drawing.Color]::FromArgb(255, 0, 255)

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Launch'
$form.FormBorderStyle = 'None'
$form.StartPosition = 'Manual'
$form.ShowInTaskbar = $false
$form.TopMost = $true
$form.Size = New-Object System.Drawing.Size((($size * $count) + ($gap * ($count - 1)) + ($pad * 2)), ($size + ($pad * 2)))
$form.BackColor = $magenta
$form.TransparencyKey = $magenta
$form.AllowTransparency = $true

function Get-BadgeX([int]$Index) { return $pad + ($Index * ($size + $gap)) }

$gp = New-Object System.Drawing.Drawing2D.GraphicsPath
0..($count - 1) | ForEach-Object { $gp.AddEllipse((Get-BadgeX $_), $pad, $size, $size) }
$form.Region = New-Object System.Drawing.Region($gp)

function Move-ToBottom {
  $s = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $form.Location = New-Object System.Drawing.Point([int](($s.Width - $form.Width) / 2), ($s.Bottom - $form.Height - 14))
}
Move-ToBottom

function Get-AppIcon([string]$Exe) {
  try {
    $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($Exe)
    if ($ico) { return $ico.ToBitmap() }
  } catch {}
  return $null
}

function New-SweepIcon {
  $bmp = New-Object System.Drawing.Bitmap 48, 48
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.Clear([System.Drawing.Color]::Transparent)
  $green = [System.Drawing.Color]::FromArgb(80, 220, 140)
  $pen = New-Object System.Drawing.Pen($green, 3.5)
  $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $g.DrawArc($pen, 8, 8, 32, 32, 40, 200)
  $g.DrawArc($pen, 8, 8, 32, 32, 220, 100)
  $brush = New-Object System.Drawing.SolidBrush($green)
  $pts1 = @(
    (New-Object System.Drawing.Point 34, 8),
    (New-Object System.Drawing.Point 42, 18),
    (New-Object System.Drawing.Point 28, 16)
  )
  $g.FillPolygon($brush, $pts1)
  $pts2 = @(
    (New-Object System.Drawing.Point 14, 40),
    (New-Object System.Drawing.Point 6, 30),
    (New-Object System.Drawing.Point 18, 32)
  )
  $g.FillPolygon($brush, $pts2)
  $g.FillEllipse($brush, 21, 21, 6, 6)
  $pen.Dispose()
  $brush.Dispose()
  $g.Dispose()
  return $bmp
}

$folderIcon = Get-AppIcon (Join-Path $env:SystemRoot 'explorer.exe')
$psIcon = Get-AppIcon (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
$scriptIcon = New-SweepIcon

$scriptPath = Join-Path $env:USERPROFILE 'admin\Clear-Apps-And-Tray.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) {
  $alt = Join-Path (Split-Path -Parent $PSCommandPath) 'Clear-Apps-And-Tray.ps1'
  if (Test-Path -LiteralPath $alt) { $scriptPath = $alt }
}

function Draw-Badge($g, [int]$x, [int]$y, $fill, $ring, $img) {
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $brush = New-Object System.Drawing.SolidBrush($fill)
  $g.FillEllipse($brush, $x, $y, $size, $size)
  $brush.Dispose()
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $pen = New-Object System.Drawing.Pen($ring, 2.5)
  $g.DrawEllipse($pen, ($x + 3), ($y + 3), ($size - 7), ($size - 7))
  $pen.Dispose()
  if ($img) {
    $iw = 28
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($img, ($x + [int](($size - $iw) / 2)), ($y + [int](($size - $iw) / 2)), $iw, $iw)
  }
}

$form.add_Paint({
  param($sender, $e)
  $e.Graphics.Clear($magenta)
  Draw-Badge $e.Graphics (Get-BadgeX 0) $pad ([System.Drawing.Color]::FromArgb(40, 40, 40)) ([System.Drawing.Color]::FromArgb(255, 196, 37)) $folderIcon
  Draw-Badge $e.Graphics (Get-BadgeX 1) $pad ([System.Drawing.Color]::FromArgb(24, 34, 50)) ([System.Drawing.Color]::FromArgb(55, 148, 230)) $psIcon
  Draw-Badge $e.Graphics (Get-BadgeX 2) $pad ([System.Drawing.Color]::FromArgb(22, 44, 30)) ([System.Drawing.Color]::FromArgb(80, 220, 140)) $scriptIcon
})

function Test-InCircle([int]$px, [int]$py, [int]$cx, [int]$cy) {
  $dx = $px - ($cx + ($size / 2.0))
  $dy = $py - ($cy + ($size / 2.0))
  return (($dx * $dx) + ($dy * $dy)) -le [Math]::Pow(($size / 2.0), 2)
}

function Run-AdminScript {
  if (-not (Test-Path -LiteralPath $scriptPath)) { return }
  $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  Start-Process -FilePath $ps -Verb RunAs -ArgumentList @(
    '-STA','-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$scriptPath`"",'-ShowReport'
  ) | Out-Null
}

$form.add_MouseDown({
  param($sender, $e)
  if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
  if (Test-InCircle $e.X $e.Y (Get-BadgeX 0) $pad) {
    Start-Process "$env:SystemRoot\explorer.exe" $env:USERPROFILE | Out-Null; return
  }
  if (Test-InCircle $e.X $e.Y (Get-BadgeX 1) $pad) {
    Start-Process (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') | Out-Null; return
  }
  if (Test-InCircle $e.X $e.Y (Get-BadgeX 2) $pad) { Run-AdminScript }
})

$form.add_Shown({ Move-ToBottom; $form.Invalidate() })
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.add_Tick({ if (-not $form.IsDisposed) { Move-ToBottom; $form.TopMost = $true } })
$timer.Start()
[void][System.Windows.Forms.Application]::Run($form)
