<#
.SYNOPSIS
  Small folder logo on screen. Click opens a File Explorer window to the user profile.
  Does not click Start and does not start the taskbar shell.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$mutex = New-Object System.Threading.Mutex($false, 'Local\AdminSetupFolderLogo')
if (-not $mutex.WaitOne(0, $false)) { return }

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Folders'
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.ShowInTaskbar = $false
$form.TopMost = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
$form.Size = New-Object System.Drawing.Size(52, 52)
$form.Opacity = 0.94

function Move-ToBottom {
  $s = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $x = [int](($s.Width - $form.Width) / 2)
  $y = $s.Bottom - $form.Height - 10
  $form.Location = New-Object System.Drawing.Point($x, $y)
}
Move-ToBottom

$btn = New-Object System.Windows.Forms.Label
$btn.Dock = [System.Windows.Forms.DockStyle]::Fill
$btn.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$btn.ForeColor = [System.Drawing.Color]::FromArgb(255, 185, 0)
$btn.BackColor = $form.BackColor
$btn.Cursor = [System.Windows.Forms.Cursors]::Hand
try { $btn.Font = New-Object System.Drawing.Font('Segoe Fluent Icons', 20) } catch {
  try { $btn.Font = New-Object System.Drawing.Font('Segoe MDL2 Assets', 20) } catch {
    $btn.Font = New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Bold)
  }
}
$btn.Text = [string][char]0xE8B7
if ([string]::IsNullOrWhiteSpace($btn.Text)) { $btn.Text = [string][char]0xE838 }
if ([string]::IsNullOrWhiteSpace($btn.Text)) { $btn.Text = 'F' }

$open = {
  $target = $env:USERPROFILE
  if (-not (Test-Path -LiteralPath $target)) { $target = $env:SystemDrive + '\' }
  Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList @("`"$target`"") | Out-Null
}
$btn.add_Click($open)
$form.add_Click($open)
$form.add_Shown({ Move-ToBottom })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 4000
$timer.add_Tick({ if (-not $form.IsDisposed) { Move-ToBottom; $form.TopMost = $true } })
$timer.Start()

$form.Controls.Add($btn)
[void][System.Windows.Forms.Application]::Run($form)
