<#
.SYNOPSIS
  Create a Desktop (and Start Menu) icon to run Admin-Setup.

.DESCRIPTION
  Places "Admin Setup.lnk" on the user Desktop and under Start Menu\Programs.
  The shortcut runs Run-Admin-Setup.cmd (elevated wipe + restart; Grok/Chrome
  ask happens only after reboot via RunOnce).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Install-AdminSetup-Shortcut.ps1
#>
[CmdletBinding()]
param(
  [switch]$DesktopOnly,
  [switch]$StartMenuOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$cmd = Join-Path $here 'Run-Admin-Setup.cmd'
$setup = Join-Path $here 'Admin-Setup.ps1'
if (-not (Test-Path $cmd)) { throw "Missing $cmd" }
if (-not (Test-Path $setup)) { throw "Missing $setup" }

$w = New-Object -ComObject WScript.Shell
$name = 'Admin Setup.lnk'

function New-AdminSetupShortcut([string]$Folder) {
  New-Item -ItemType Directory -Force -Path $Folder | Out-Null
  $path = Join-Path $Folder $name
  $sc = $w.CreateShortcut($path)
  $sc.TargetPath = $cmd
  $sc.WorkingDirectory = $here
  $sc.WindowStyle = 1
  $sc.Description = 'Wipe removable apps, restart, then offer Grok Bot + Chrome'
  # Prefer powershell icon if cmd has none useful
  $sc.IconLocation = "$env:SystemRoot\System32\imageres.dll,109"
  $sc.Save()
  return $path
}

$made = @()
if (-not $StartMenuOnly) {
  $desk = [Environment]::GetFolderPath('Desktop')
  $made += (New-AdminSetupShortcut $desk)
}
if (-not $DesktopOnly) {
  $sm = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
  $made += (New-AdminSetupShortcut $sm)
}

Write-Host 'Created:'
$made | ForEach-Object { Write-Host "  $_" }
Write-Host 'Double-click Admin Setup to run the wipe (UAC will prompt). Download ask is after restart only.'
