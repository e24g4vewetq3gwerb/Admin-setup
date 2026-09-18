<#
.SYNOPSIS
  Windhawk tray: keep only the Show Hidden Icons (up-arrow) chevron.

.DESCRIPTION
  Configures Windhawk mod taskbar-tray-system-icon-tweaks so Windows 11 hides
  language, network, volume, battery, bell, and Show Desktop from the system
  tray. The overflow chevron stays.

  Requires admin. Installs Windhawk via winget if missing, downloads the
  prebuilt 1.3 x64 mod DLL when needed, writes registry settings, then
  restarts Windhawk and Explorer.

  CRITICAL: Include must be REG_SZ "explorer.exe" (REG_MULTI_SZ breaks injection).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Restore-TrayArrowOnly.ps1
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

function Test-IsAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
  Write-Host 'Re-launching elevated...'
  Start-Process powershell.exe -Verb RunAs -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
  ) | Out-Null
  return
}

$mods64 = 'C:\ProgramData\Windhawk\Engine\Mods\64'
$storeDll = 'taskbar-tray-system-icon-tweaks_1.3_229577.dll'
$localDll = 'local@taskbar-tray-system-icon-tweaks_1.3_380409.dll'
$dllUrl = 'https://mods.windhawk.net/mods/taskbar-tray-system-icon-tweaks/1.3_64.dll'
$whExe = 'C:\Program Files\Windhawk\Windhawk.exe'

if (-not (Test-Path $whExe)) {
  Write-Host 'Installing Windhawk (winget)...'
  winget install --id RamenSoftware.Windhawk -e --accept-package-agreements --accept-source-agreements
  if (-not (Test-Path $whExe)) { throw 'Windhawk install failed' }
}

New-Item -ItemType Directory -Force -Path $mods64 | Out-Null
$storePath = Join-Path $mods64 $storeDll
if (-not (Test-Path $storePath) -or ((Get-Item $storePath).Length -lt 10000)) {
  Write-Host "Downloading $storeDll ..."
  Invoke-WebRequest -Uri $dllUrl -OutFile $storePath -UseBasicParsing
}
Copy-Item $storePath (Join-Path $mods64 $localDll) -Force

Get-Process windhawk -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

$dwords = @{
  hideVolumeIcon                 = 1
  hideNetworkIcon                = 1
  hideBatteryIcon                = 1
  grayscaleBatteryIcon           = 0
  hideMicrophoneIcon             = 1
  hideGeolocationIcon            = 1
  hideStudioEffectsIcon          = 1
  hideRecallIcon                 = 1
  hideLanguageBar                = 1
  hideLanguageSupplementaryIcons = 1
  showDesktopButtonWidth         = 0
}
$t = [int]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
$ids = @('taskbar-tray-system-icon-tweaks', 'local@taskbar-tray-system-icon-tweaks')

foreach ($id in $ids) {
  $root = "HKLM:\SOFTWARE\Windhawk\Engine\Mods\$id"
  if (-not (Test-Path $root)) { New-Item -Path $root -Force | Out-Null }
  Remove-ItemProperty -Path $root -Name 'Include' -ErrorAction SilentlyContinue
  New-ItemProperty -Path $root -Name 'Include' -PropertyType String -Value 'explorer.exe' -Force | Out-Null
  New-ItemProperty -Path $root -Name 'Disabled' -PropertyType DWord -Value 0 -Force | Out-Null
  New-ItemProperty -Path $root -Name 'Version' -PropertyType String -Value '1.3' -Force | Out-Null
  New-ItemProperty -Path $root -Name 'Architecture' -PropertyType String -Value 'x86-64' -Force | Out-Null
  New-ItemProperty -Path $root -Name 'LoggingEnabled' -PropertyType DWord -Value 1 -Force | Out-Null
  New-ItemProperty -Path $root -Name 'SettingsChangeTime' -PropertyType DWord -Value $t -Force | Out-Null

  foreach ($hive in @('Mods', 'ModsWritable')) {
    $base = "HKLM:\SOFTWARE\Windhawk\Engine\$hive\$id"
    $set = Join-Path $base 'Settings'
    if (-not (Test-Path $base)) { New-Item -Path $base -Force | Out-Null }
    if (-not (Test-Path $set)) { New-Item -Path $set -Force | Out-Null }
    New-ItemProperty -Path $base -Name 'Disabled' -PropertyType DWord -Value 0 -Force | Out-Null
    New-ItemProperty -Path $base -Name 'SettingsChangeTime' -PropertyType DWord -Value $t -Force | Out-Null
    foreach ($k in $dwords.Keys) {
      New-ItemProperty -Path $set -Name $k -PropertyType DWord -Value $dwords[$k] -Force | Out-Null
    }
    New-ItemProperty -Path $set -Name 'hideBellIcon' -PropertyType String -Value 'always' -Force | Out-Null
  }

  $writableDir = "C:\ProgramData\Windhawk\Engine\ModsWritable\$id"
  New-Item -ItemType Directory -Force -Path $writableDir | Out-Null
  [IO.File]::WriteAllText((Join-Path $writableDir 'mod.ini'), "[mod]`r`nEnabled=1`r`n")
}

New-ItemProperty -Path 'HKLM:\SOFTWARE\Windhawk\Engine\Mods\taskbar-tray-system-icon-tweaks' `
  -Name 'LibraryFileName' -PropertyType String -Value $storeDll -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\Windhawk\Engine\Mods\local@taskbar-tray-system-icon-tweaks' `
  -Name 'LibraryFileName' -PropertyType String -Value $localDll -Force | Out-Null

[IO.File]::WriteAllText(
  'C:\ProgramData\Windhawk\userprofile.json',
  '{"app":{},"mods":{"taskbar-tray-system-icon-tweaks":{"version":"1.3"}}}'
)

Start-Process $whExe
Start-Sleep -Seconds 2
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }

Write-Host 'Restore-TrayArrowOnly done. Right tray should show only the up-arrow chevron.'
