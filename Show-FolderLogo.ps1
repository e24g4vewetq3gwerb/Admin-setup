<#
.SYNOPSIS
  Two transparent logos at the bottom: folder (user profile) and PowerShell.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$mutex = New-Object System.Threading.Mutex($false, 'Local\AdminSetupFolderLogo')
if (-not $mutex.WaitOne(0, $false)) { return }

$clear = [System.Drawing.Color]::FromArgb(255, 0, 255)
$yellow = [System.Drawing.Color]::FromArgb(255, 185, 0)
$blue = [System.Drawing.Color]::FromArgb(80, 170, 255)

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Launch'
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.ShowInTaskbar = $false
$form.TopMost = $true
$form.Size = New-Object System.Drawing.Size(120, 56)
$form.BackColor = $clear
$form.TransparencyKey = $clear
$form.AllowTransparency = $true

function Move-ToBottom {
  $s = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $x = [int](($s.Width - $form.Width) / 2)
  $y = $s.Bottom - $form.Height - 10
  $form.Location = New-Object System.Drawing.Point($x, $y)
}
Move-ToBottom

$folderGlyph = [string][char]0xE8B7
$psGlyph = [string][char]0xE756
$font = $null
foreach ($name in @('Segoe Fluent Icons','Segoe MDL2 Assets')) {
  try { $font = New-Object System.Drawing.Font($name, 20); break } catch {}
}
if (-not $font) {
  $font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
  $folderGlyph = 'F'
  $psGlyph = 'P'
}

function Get-Half([int]$index) {
  $w = [int]($form.ClientSize.Width / 2)
  return New-Object System.Drawing.Rectangle(($index * $w), 0, $w, $form.ClientSize.Height)
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

$form.add_Paint({
  param($sender, $e)
  $g = $e.Graphics
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
  $sf = New-Object System.Drawing.StringFormat
  $sf.Alignment = [System.Drawing.StringAlignment]::Center
  $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
  $items = @(
    @{ Rect = (Get-Half 0); Color = $yellow; Text = $folderGlyph },
    @{ Rect = (Get-Half 1); Color = $blue;   Text = $psGlyph }
  )
  foreach ($item in $items) {
    $r = $item.Rect
    $pad = 6
    $oval = New-Object System.Drawing.Rectangle(($r.X + $pad), ($r.Y + $pad), ($r.Width - (2 * $pad) - 1), ($r.Height - (2 * $pad) - 1))
    $pen = New-Object System.Drawing.Pen($item.Color, 2)
    $g.DrawEllipse($pen, $oval)
    $pen.Dispose()
    $brush = New-Object System.Drawing.SolidBrush($item.Color)
    $g.DrawString($item.Text, $font, $brush, [System.Drawing.RectangleF]$r, $sf)
    $brush.Dispose()
  }
  $sf.Dispose()
})

$form.add_MouseClick({
  param($sender, $e)
  if ($e.X -lt [int]($form.ClientSize.Width / 2)) { Open-Folder } else { Open-PowerShell }
})
$form.add_Shown({ Move-ToBottom; $form.Invalidate() })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 4000
$timer.add_Tick({ if (-not $form.IsDisposed) { Move-ToBottom; $form.TopMost = $true } })
$timer.Start()

[void][System.Windows.Forms.Application]::Run($form)
