<#
.SYNOPSIS
  Tiny Windows-logo control at the bottom of the screen. Click opens Start.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$mutex = New-Object System.Threading.Mutex($false, 'Local\AdminSetupStartLogo')
if (-not $mutex.WaitOne(0, $false)) { return }

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class StartLogoKbd {
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
  public static void OpenStart() {
    keybd_event(0x5B, 0, 0, UIntPtr.Zero);
    keybd_event(0x5B, 0, 2, UIntPtr.Zero);
  }
}
'@

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Start'
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.ShowInTaskbar = $false
$form.TopMost = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
$form.Size = New-Object System.Drawing.Size(44, 44)
$form.Opacity = 0.92

function Move-ToBottom {
  $s = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $x = [int](($s.Width - $form.Width) / 2)
  $y = $s.Bottom - $form.Height - 8
  $form.Location = New-Object System.Drawing.Point($x, $y)
}
Move-ToBottom

$btn = New-Object System.Windows.Forms.Label
$btn.Dock = [System.Windows.Forms.DockStyle]::Fill
$btn.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$btn.ForeColor = [System.Drawing.Color]::White
$btn.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
$btn.Cursor = [System.Windows.Forms.Cursors]::Hand
try {
  $btn.Font = New-Object System.Drawing.Font('Segoe Fluent Icons', 18)
} catch {
  try { $btn.Font = New-Object System.Drawing.Font('Segoe MDL2 Assets', 18) } catch {
    $btn.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
  }
}
$btn.Text = [string][char]0xE782
if ([string]::IsNullOrWhiteSpace($btn.Text)) { $btn.Text = [string][char]0xE799 }
if ([string]::IsNullOrWhiteSpace($btn.Text)) { $btn.Text = 'W' }

$open = {
  try { [StartLogoKbd]::OpenStart() } catch { [System.Windows.Forms.SendKeys]::SendWait('^{ESC}') }
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
