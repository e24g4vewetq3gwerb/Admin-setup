<#!
.SYNOPSIS
  One-shot wipe + harden: remove apps, restart, then offer latest Grok Bot + Chrome (install + pin).

.DESCRIPTION
  Entry point for the admin package. Intended flow:
    1) Harden-ITAdminPC.ps1 (optional)
    2) Cleanup-Background.ps1 -KeepProfile DriversOnly -UninstallNotKept (wipe removable apps)
    3) Unpin-And-Remove-OEM.ps1
    4) Clear-Desktop.ps1 (black wallpaper, no desktop icons incl Recycle Bin)
    5) Minimal-Taskbar.ps1 -StartOnly (clear pins for reboot)
    6) On -Restart/-RestartIfNeeded: register Offer-GrokAndChrome.ps1 RunOnce
       After reboot: ask Yes/No for latest Grok Bot + Google Chrome; on Yes install both and pin.

  -Audit              Report only (default)
  -Apply              Apply harden + cleanup service/startup changes
  -UninstallNotKept   Wipe apps outside DriversOnly keep/protect list
  -Restart            Reboot when finished
  -RestartIfNeeded    Reboot only if Apply/uninstall ran
  -SkipHarden / -SkipCleanup / -SkipUnpin / -SkipTaskbar
  -SkipWindhawkTray   Skip Windhawk during wipe pass
  -DockChromeCursorGrok  Legacy 3-app dock (usually leave off; offer script pins Chrome+Grok after reboot)
  -StartOnly          Clear pins during wipe (default)

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Admin-Setup.ps1 -Apply -UninstallNotKept -RestartIfNeeded
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [switch]$Audit,
  [switch]$Apply,
  [switch]$UninstallNotKept,
  [switch]$Restart,
  [switch]$RestartIfNeeded,
  [switch]$SkipHarden,
  [switch]$SkipCleanup,
  [switch]$SkipUnpin,
  [switch]$SkipTaskbar,
  [switch]$SkipWindhawkTray,
  [switch]$DockChromeCursorGrok,
  [switch]$StartOnly,
  [ValidateSet('Minimal','DriversOnly')]
  [string]$KeepProfile = 'DriversOnly'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
if (-not $Audit -and -not $Apply -and -not $UninstallNotKept) { $Audit = $true }

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $here 'Admin-Setup.log'
function L([string]$m) {
  $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $m
  $line | Tee-Object -FilePath $log -Append
}

function Test-IsAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

L "==== Admin-Setup Audit=$Audit Apply=$Apply UninstallNotKept=$UninstallNotKept KeepProfile=$KeepProfile elevated=$(Test-IsAdmin) ===="

if (($Apply -or $UninstallNotKept) -and -not (Test-IsAdmin)) {
  L 'Re-launching elevated...'
  $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
  if ($Apply) { $args += '-Apply' }
  if ($UninstallNotKept) { $args += '-UninstallNotKept' }
  if ($Restart) { $args += '-Restart' }
  if ($RestartIfNeeded) { $args += '-RestartIfNeeded' }
  if ($SkipHarden) { $args += '-SkipHarden' }
  if ($SkipCleanup) { $args += '-SkipCleanup' }
  if ($SkipUnpin) { $args += '-SkipUnpin' }
  if ($SkipTaskbar) { $args += '-SkipTaskbar' }
  if ($SkipWindhawkTray) { $args += '-SkipWindhawkTray' }
  if ($DockChromeCursorGrok) { $args += '-DockChromeCursorGrok' }
  if ($StartOnly) { $args += '-StartOnly' }
  $args += @('-KeepProfile', $KeepProfile)
  if ($WhatIfPreference) { $args += '-WhatIf' }
  Start-Process powershell.exe -Verb RunAs -ArgumentList $args | Out-Null
  return
}

$harden = Join-Path $here 'Harden-ITAdminPC.ps1'
$cleanup = Join-Path $here 'Cleanup-Background.ps1'
$unpin = Join-Path $here 'Unpin-And-Remove-OEM.ps1'
$taskbar = Join-Path $here 'Minimal-Taskbar.ps1'
$offer = Join-Path $here 'Offer-GrokAndChrome.ps1'
if (-not (Test-Path $offer)) { $offer = Join-Path $here 'Offer-GrokBot.ps1' }

$script:TaskbarOrCleanupApplied = $false

function Invoke-Step {
  param([string]$Path, [string[]]$ArgList, [string]$Label)
  if (-not (Test-Path $Path)) { L "MISSING $Label -> $Path"; return }
  L "START $Label"
  $all = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $Path) + $ArgList
  $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $all -Wait -PassThru -NoNewWindow
  L "END $Label exit=$($p.ExitCode)"
}

if (-not $SkipHarden) {
  $hArgs = @()
  if ($Apply) { $hArgs += '-Apply' } else { $hArgs += '-Audit' }
  Invoke-Step -Path $harden -ArgList $hArgs -Label 'Harden-ITAdminPC'
}

if (-not $SkipCleanup) {
  $cArgs = @('-KeepProfile', $KeepProfile)
  if ($Apply) { $cArgs += '-Apply'; $script:TaskbarOrCleanupApplied = $true }
  if ($UninstallNotKept) { $cArgs += '-UninstallNotKept'; $script:TaskbarOrCleanupApplied = $true }
  if (-not $Apply -and -not $UninstallNotKept) { $cArgs += '-Audit' }
  Invoke-Step -Path $cleanup -ArgList $cArgs -Label 'Cleanup-Background'
}

if (-not $SkipUnpin -and ($Apply -or $UninstallNotKept)) {
  Invoke-Step -Path $unpin -ArgList @() -Label 'Unpin-And-Remove-OEM'
}

$clearDesk = Join-Path $here 'Clear-Desktop.ps1'
if (($Apply -or $UninstallNotKept) -and (Test-Path $clearDesk)) {
  Invoke-Step -Path $clearDesk -ArgList @('-Apply') -Label 'Clear-Desktop'
  $script:TaskbarOrCleanupApplied = $true
}

if (-not $SkipTaskbar -and ($Apply -or $UninstallNotKept -or $Audit)) {
  $tArgs = @()
  if ($Apply -or $UninstallNotKept) {
    $tArgs += '-Apply'
    $script:TaskbarOrCleanupApplied = $true
  } else {
    $tArgs += '-Audit'
  }
  if ($SkipWindhawkTray) { $tArgs += '-SkipWindhawkTray' }
  if ($DockChromeCursorGrok) {
    $tArgs += '-DockChromeCursorGrok'
  } else {
    # Wipe pass: Start only; post-reboot offer pins Chrome+Grok if user says Yes
    $tArgs += '-StartOnly'
  }
  Invoke-Step -Path $taskbar -ArgList $tArgs -Label 'Minimal-Taskbar'
}

L '==== Admin-Setup finished ===='
Write-Host ''
Write-Host 'Admin-Setup finished. See CSVs/logs under this scripts folder.'
Write-Host "Log: $log"
Write-Host 'Flow: wipe apps -> restart -> offer latest Grok Bot + Chrome -> install + pin if Yes'

# After restart: offer Grok + Chrome
if (($Restart -or $RestartIfNeeded) -and ($Apply -or $UninstallNotKept) -and (Test-Path $offer)) {
  L 'Register Offer-GrokAndChrome RunOnce for next logon'
  Invoke-Step -Path $offer -ArgList @('-RegisterRunOnce') -Label 'Offer-GrokAndChrome-Register'
}

$alreadyScheduled = $false
if ($Restart) {
  L 'Restart requested - 60s'
  shutdown.exe /r /t 60 /c 'Admin-Setup: restart to finish wipe; then offer Grok Bot + Chrome'
  $alreadyScheduled = $true
} elseif ($RestartIfNeeded -and $script:TaskbarOrCleanupApplied -and ($Apply -or $UninstallNotKept)) {
  L 'RestartIfNeeded: scheduling shutdown /r /t 60'
  Write-Host 'Restarting in 60 seconds. Run: shutdown /a   to cancel.'
  shutdown.exe /r /t 60 /c 'Admin-Setup: restart to finish wipe; then offer Grok Bot + Chrome'
  $alreadyScheduled = $true
} elseif ($RestartIfNeeded) {
  L 'RestartIfNeeded set but no Apply taskbar/cleanup ran — skip reboot'
}

if ($alreadyScheduled) {
  L 'Reboot scheduled (shutdown /a to cancel)'
}
