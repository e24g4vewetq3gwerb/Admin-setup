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

Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
public static class DllIcon {
  [DllImport("Shell32.dll", CharSet=CharSet.Auto)]
  static extern int ExtractIconEx(string file, int index, IntPtr[] large, IntPtr[] small, int n);
  [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr hIcon);
  public static Bitmap FromDll(string path, int index, int px) {
    IntPtr[] large = new IntPtr[1];
    ExtractIconEx(path, index, large, null, 1);
    if (large[0] == IntPtr.Zero) return null;
    Icon ico = Icon.FromHandle(large[0]);
    Bitmap bmp = new Bitmap(ico.ToBitmap(), px, px);
    DestroyIcon(large[0]);
    return bmp;
  }
}
'@

$size = 58; $gap = 16; $pad = 2; $count = 3
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Launch'
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.ShowInTaskbar = $false
$form.TopMost = $true
$form.Size = New-Object System.Drawing.Size((($size * $count) + ($gap * ($count - 1)) + ($pad * 2)), ($size + ($pad * 2)))
$form.BackColor = [System.Drawing.Color]::Black
function Get-BadgeX([int]$Index) { return $pad + ($Index * ($size + $gap)) }
$gp = New-Object System.Drawing.Drawing2D.GraphicsPath
0..($count - 1) | ForEach-Object { $gp.AddEllipse((Get-BadgeX $_), $pad, $size, $size) }
$form.Region = New-Object System.Drawing.Region($gp)
function Move-ToBottom {
  $s = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $form.Location = New-Object System.Drawing.Point([int](($s.Width - $form.Width) / 2), ($s.Bottom - $form.Height - 12))
}
Move-ToBottom
function Get-AppIcon([string]$Exe) {
  try { $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($Exe); if ($ico) { return $ico.ToBitmap() } } catch {}
  return $null
}
function Get-GearIcon {
  foreach ($dll in @((Join-Path $env:SystemRoot 'System32\imageres.dll'), (Join-Path $env:SystemRoot 'System32\shell32.dll'))) {
    foreach ($idx in @(109, 63, 64, 21, 30, 72, 73, 15)) {
      try { $bmp = [DllIcon]::FromDll($dll, $idx, 32); if ($bmp) { return $bmp } } catch {}
    }
  }
  return $null
}
$scriptPath = Join-Path $env:USERPROFILE 'admin\Clear-Apps-And-Tray.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) {
  $alt = Join-Path (Split-Path -Parent $PSCommandPath) 'Clear-Apps-And-Tray.ps1'
  if (Test-Path -LiteralPath $alt) { $scriptPath = $alt }
}
$folderIcon = Get-AppIcon (Join-Path $env:SystemRoot 'explorer.exe')
$psIcon = Get-AppIcon (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
$scriptIcon = Get-GearIcon
if (-not $scriptIcon) { $scriptIcon = $psIcon }
$yellow = [System.Drawing.Color]::FromArgb(255, 196, 37)
$blue = [System.Drawing.Color]::FromArgb(55, 148, 230)
$green = [System.Drawing.Color]::FromArgb(46, 204, 113)
function Draw-Badge($g, [int]$x, [int]$y, $fill, $ring, $img) {
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $brush = New-Object System.Drawing.SolidBrush($fill)
  $g.FillEllipse($brush, $x, $y, $size, $size)
  $brush.Dispose()
  $pen = New-Object System.Drawing.Pen($ring, 3)
  $g.DrawEllipse($pen, ($x + 2), ($y + 2), ($size - 5), ($size - 5))
  $pen.Dispose()
  if ($img) { $g.DrawImage($img, ($x + 15), ($y + 15), 28, 28) }
}
$form.add_Paint({
  param($sender, $e)
  $e.Graphics.Clear([System.Drawing.Color]::Black)
  Draw-Badge $e.Graphics (Get-BadgeX 0) $pad ([System.Drawing.Color]::FromArgb(36,36,36)) $yellow $folderIcon
  Draw-Badge $e.Graphics (Get-BadgeX 1) $pad ([System.Drawing.Color]::FromArgb(22,32,48)) $blue $psIcon
  Draw-Badge $e.Graphics (Get-BadgeX 2) $pad ([System.Drawing.Color]::FromArgb(20,40,28)) $green $scriptIcon
})
function Test-InCircle([int]$px, [int]$py, [int]$cx, [int]$cy) {
  $dx = $px - ($cx + ($size / 2.0)); $dy = $py - ($cy + ($size / 2.0))
  return (($dx * $dx) + ($dy * $dy)) -le [Math]::Pow(($size / 2.0), 2)
}
function Open-Folder {
  $target = $env:USERPROFILE
  if (-not (Test-Path -LiteralPath $target)) { $target = $env:SystemDrive + '\' }
  Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList @("`"$target`"") | Out-Null
}
function Open-PowerShell {
  Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -WorkingDirectory $env:USERPROFILE | Out-Null
}
function Run-AdminScript {
  if (-not (Test-Path -LiteralPath $scriptPath)) { return }
  $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  Start-Process -FilePath $ps -Verb RunAs -WindowStyle Hidden -ArgumentList @(
    '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$scriptPath`"",'-ShowReport'
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
