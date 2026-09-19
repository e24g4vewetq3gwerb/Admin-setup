<#
.SYNOPSIS
  Three circular badges: folder, PowerShell, rerun Admin script.
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
$count = 3

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Launch'
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.ShowInTaskbar = $false
$form.TopMost = $true
$form.Size = New-Object System.Drawing.Size((($size * $count) + ($gap * ($count - 1)) + ($pad * 2)), ($size + ($pad * 2)))
$form.BackColor = [System.Drawing.Color]::Black

function Get-BadgeX([int]$Index) { return $pad + ($Index * ($size + $gap)) }

$path = New-Object System.Drawing.Drawing2D.GraphicsPath
0..($count - 1) | ForEach-Object { $path.AddEllipse((Get-BadgeX $_), $pad, $size, $size) }
$form.Region = New-Object System.Drawing.Region($path)

function Move-ToBottom {
  $s = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $x = [int](($s.Width - $form.Width) / 2)
  $y = $s.Bottom - $form.Height - 12
  $form.Location = New-Object System.Drawing.Point($x, $y)
}
Move-ToBottom

function Get-AppIcon([string]$Exe) {
  try {
    $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($Exe)
    if ($ico) { return $ico.ToBitmap() }
  } catch {}
  return $null
}

$scriptPath = Join-Path $env:USERPROFILE 'admin\Clear-Apps-And-Tray.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) {
  $here = Split-Path -Parent $PSCommandPath
  $alt = Join-Path $here 'Clear-Apps-And-Tray.ps1'
  if (Test-Path -LiteralPath $alt) { $scriptPath = $alt }
}

$folderIcon = Get-AppIcon (Join-Path $env:SystemRoot 'explorer.exe')
$psIcon = Get-AppIcon (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
$scriptIcon = $null
if (Test-Path -LiteralPath $scriptPath) { $scriptIcon = Get-AppIcon $scriptPath }
if (-not $scriptIcon) { $scriptIcon = $psIcon }

$yellow = [System.Drawing.Color]::FromArgb(255, 196, 37)
$blue = [System.Drawing.Color]::FromArgb(55, 148, 230)
$green = [System.Drawing.Color]::FromArgb(46, 204, 113)
$fillA = [System.Drawing.Color]::FromArgb(36, 36, 36)
$fillB = [System.Drawing.Color]::FromArgb(22, 32, 48)
$fillC = [System.Drawing.Color]::FromArgb(20, 40, 28)

function Draw-Badge($g, [int]$x, [int]$y, $fill, $ring, $img) {
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $brush = New-Object System.Drawing.SolidBrush($fill)
  $g.FillEllipse($brush, $x, $y, $size, $size)
  $brush.Dispose()
  $pen = New-Object System.Drawing.Pen($ring, 3)
  $g.DrawEllipse($pen, ($x + 2), ($y + 2), ($size - 5), ($size - 5))
  $pen.Dispose()
  if ($img) {
    $iw = 28
    $g.DrawImage($img, ($x + [int](($size - $iw) / 2)), ($y + [int](($size - $iw) / 2)), $iw, $iw)
  }
}

$form.add_Paint({
  param($sender, $e)
  $e.Graphics.Clear([System.Drawing.Color]::Black)
  Draw-Badge $e.Graphics (Get-BadgeX 0) $pad $fillA $yellow $folderIcon
  Draw-Badge $e.Graphics (Get-BadgeX 1) $pad $fillB $blue $psIcon
  Draw-Badge $e.Graphics (Get-BadgeX 2) $pad $fillC $green $scriptIcon
})

function Test-InCircle([int]$px, [int]$py, [int]$cx, [int]$cy) {
  $dx = $px - ($cx + ($size / 2.0))
  $dy = $py - ($cy + ($size / 2.0))
  return (($dx * $dx) + ($dy * $dy)) -le [Math]::Pow(($size / 2.0), 2)
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
function Run-AdminScript {
  if (-not (Test-Path -LiteralPath $scriptPath)) { return }
  $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  Start-Process -FilePath $ps -Verb RunAs -ArgumentList @(
    '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$scriptPath`""
  ) | Out-Null
}

$form.add_MouseDown({
  param($sender, $e)
  if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
  if (Test-InCircle $e.X $e.Y (Get-BadgeX 0) $pad) { Open-Folder; return }
  if (Test-InCircle $e.X $e.Y (Get-BadgeX 1) $pad) { Open-PowerShell; return }
  if (Test-InCircle $e.X $e.Y (Get-BadgeX 2) $pad) { Run-AdminScript }
})

$form.add_Shown({ Move-ToBottom; $form.Invalidate() })
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.add_Tick({ if (-not $form.IsDisposed) { Move-ToBottom; $form.TopMost = $true } })
$timer.Start()

[void][System.Windows.Forms.Application]::Run($form)
