<#
.SYNOPSIS
  One-shot IT admin PC setup: harden + cleanup + OEM unpin + minimal taskbar (Start + up-arrow).

.DESCRIPTION
  Entry point for the admin package. Runs in order:
    1) Harden-ITAdminPC.ps1
    2) Cleanup-Background.ps1
    3) Unpin-And-Remove-OEM.ps1 (also invoked from Cleanup on -Apply)
    4) Minimal-Taskbar.ps1 (default Start + up-arrow only; optional -DockChromeCursorGrok)
    5) On -Restart/-RestartIfNeeded: register Offer-GrokBot.ps1 (ask to download if missing at next logon)

  -Audit              Report only (default)
  -Apply              Apply harden + cleanup service/startup changes
  -UninstallNotKept   Uninstall apps outside Minimal keep list
  -Restart            Reboot when finished
  -RestartIfNeeded    Reboot only if child scripts reported changes / taskbar+cleanup Apply ran
  -SkipHarden         Skip harden step
  -SkipCleanup        Skip cleanup step
  -SkipUnpin          Skip dedicated Edge/Outlook/Store step
  -SkipTaskbar        Skip minimal taskbar step
  -SkipWindhawkTray   Skip Windhawk up-arrow-only tray inside Minimal-Taskbar
  -DockChromeCursorGrok  Pass through: pin Chrome/Cursor/Grok (legacy dock) instead of StartOnly
  -StartOnly          Pass through to Minimal-Taskbar (default on Apply/Uninstall)

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Admin-Setup.ps1 -Audit
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Admin-Setup.ps1 -Apply -UninstallNotKept -RestartIfNeeded
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Admin-Setup.ps1 -Apply -DockChromeCursorGrok
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
  [switch]$StartOnly
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

L "==== Admin-Setup Audit=$Audit Apply=$Apply UninstallNotKept=$UninstallNotKept DockChromeCursorGrok=$DockChromeCursorGrok StartOnly=$StartOnly elevated=$(Test-IsAdmin) ===="

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
  if ($WhatIfPreference) { $args += '-WhatIf' }
  Start-Process powershell.exe -Verb RunAs -ArgumentList $args | Out-Null
  return
}

$harden = Join-Path $here 'Harden-ITAdminPC.ps1'
$cleanup = Join-Path $here 'Cleanup-Background.ps1'
$unpin = Join-Path $here 'Unpin-And-Remove-OEM.ps1'
$taskbar = Join-Path $here 'Minimal-Taskbar.ps1'
$offerGrok = Join-Path $here 'Offer-GrokBot.ps1'

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
  $cArgs = @()
  if ($Apply) { $cArgs += '-Apply'; $script:TaskbarOrCleanupApplied = $true }
  if ($UninstallNotKept) { $cArgs += '-UninstallNotKept'; $script:TaskbarOrCleanupApplied = $true }
  if (-not $Apply -and -not $UninstallNotKept) { $cArgs += '-Audit' }
  Invoke-Step -Path $cleanup -ArgList $cArgs -Label 'Cleanup-Background'
}

if (-not $SkipUnpin -and ($Apply -or $UninstallNotKept)) {
  Invoke-Step -Path $unpin -ArgList @() -Label 'Unpin-And-Remove-OEM'
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
    # Default: Start + up-arrow only
    $tArgs += '-StartOnly'
  }
  Invoke-Step -Path $taskbar -ArgList $tArgs -Label 'Minimal-Taskbar'
}

L '==== Admin-Setup finished ===='
Write-Host ''
Write-Host 'Admin-Setup finished. See CSVs/logs under this scripts folder.'
Write-Host "Log: $log"
Write-Host 'Default taskbar goal: Start button + up-arrow chevron only'


# After restart: ask to download Grok Bot if missing
if (($Restart -or $RestartIfNeeded) -and ($Apply -or $UninstallNotKept) -and (Test-Path $offerGrok)) {
  L 'Register Offer-GrokBot RunOnce for next logon'
  Invoke-Step -Path $offerGrok -ArgList @('-RegisterRunOnce') -Label 'Offer-GrokBot-Register'
}

# Restart policy: -Restart always; -RestartIfNeeded when Apply path ran taskbar/cleanup
$alreadyScheduled = $false
if ($Restart) {
  L 'Restart requested - 60s'
  shutdown.exe /r /t 60 /c 'Admin-Setup: restart to finish applying changes'
  $alreadyScheduled = $true
} elseif ($RestartIfNeeded -and $script:TaskbarOrCleanupApplied -and ($Apply -or $UninstallNotKept)) {
  L 'RestartIfNeeded: scheduling shutdown /r /t 60 after Apply taskbar/cleanup'
  Write-Host 'Restarting in 60 seconds to finish applying changes. Run: shutdown /a   to cancel.'
  shutdown.exe /r /t 60 /c 'Admin-Setup: restart to finish applying changes'
  $alreadyScheduled = $true
} elseif ($RestartIfNeeded) {
  L 'RestartIfNeeded set but no Apply taskbar/cleanup ran — skip reboot (child may have scheduled separately)'
}

if ($alreadyScheduled) {
  L 'Reboot scheduled (shutdown /a to cancel)'
}
