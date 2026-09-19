<#
.SYNOPSIS
  Remove the leftover Settings > Installed apps rows that survive a wipe:
  Snipping Tool (Microsoft.ScreenSketch) and Windows Package Manager Source (winget) V2
  (Microsoft.Winget.Source).

.NOTES
  Microsoft.DesktopAppInstaller (App Installer / winget.exe) is NonRemovable on current
  Windows. Remove-AppxPackage returns 0x80070032. This script does not delete WindowsApps.
  Run elevated.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Continue'

function Test-IsAdmin {
  $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-IsAdmin)) {
  Write-Host 'Not admin. Right-click PowerShell -> Run as administrator, then re-run.' -ForegroundColor Red
  return
}

Write-Host '=== Before ===' -ForegroundColor Cyan
Get-AppxPackage -AllUsers | Where-Object {
  $_.Name -match 'ScreenSketch|Snipping|Winget.Source|DesktopAppInstaller'
} | Select-Object Name, Version, NonRemovable | Format-Table -AutoSize

# Snipping Tool
Get-AppxPackage *ScreenSketch* | Remove-AppxPackage -ErrorAction SilentlyContinue
Get-AppxPackage -AllUsers *ScreenSketch* | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
Get-AppxProvisionedPackage -Online |
  Where-Object { $_.DisplayName -match 'ScreenSketch|Snipping' } |
  ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue }

# winget catalog source (the 4 MB Settings row), not App Installer
if (Get-Command winget -ErrorAction SilentlyContinue) {
  winget source remove --name winget 2>$null
  winget uninstall --name "Windows Package Manager Source (winget) V2" --accept-source-agreements --disable-interactivity --silent 2>$null
  winget uninstall --id Microsoft.Winget.Source --accept-source-agreements --disable-interactivity --silent 2>$null
}
Get-AppxPackage *Winget.Source* | Remove-AppxPackage -ErrorAction SilentlyContinue
Get-AppxPackage -AllUsers *Winget.Source* | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
Get-AppxProvisionedPackage -Online |
  Where-Object { $_.DisplayName -match 'Winget.Source|Package Manager Source' } |
  ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue }

Write-Host "`n=== After ===" -ForegroundColor Yellow
Get-AppxPackage -AllUsers | Where-Object {
  $_.Name -match 'ScreenSketch|Winget.Source|DesktopAppInstaller'
} | Select-Object Name, Version, NonRemovable | Format-Table -AutoSize
Write-Host 'DesktopAppInstaller remaining is expected (0x80070032 / NonRemovable).' -ForegroundColor DarkYellow
