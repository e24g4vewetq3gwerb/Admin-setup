<#
.SYNOPSIS
  One-shot IT admin PC setup: harden + cleanup + Edge/Outlook/Store taskbar removal.

.DESCRIPTION
  Entry point for the admin package. Runs in order:
    1) Harden-ITAdminPC.ps1
    2) Cleanup-Background.ps1
    3) Unpin-And-Remove-OEM.ps1 (also invoked from Cleanup on -Apply)

  -Audit              Report only (default)
  -Apply              Apply harden + cleanup service/startup changes
  -UninstallNotKept   Uninstall apps outside Minimal keep list
  -Restart            Reboot when finished
  -RestartIfNeeded    Reboot only if child scripts reported changes
  -SkipHarden         Skip harden step
  -SkipCleanup        Skip cleanup step
  -SkipUnpin          Skip dedicated Edge/Outlook/Store step

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Admin-Setup.ps1 -Audit
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
  [switch]$SkipUnpin
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

L "==== Admin-Setup Audit=$Audit Apply=$Apply UninstallNotKept=$UninstallNotKept elevated=$(Test-IsAdmin) ===="

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
  if ($WhatIfPreference) { $args += '-WhatIf' }
  Start-Process powershell.exe -Verb RunAs -ArgumentList $args | Out-Null
  return
}

$harden = Join-Path $here 'Harden-ITAdminPC.ps1'
$cleanup = Join-Path $here 'Cleanup-Background.ps1'
$unpin = Join-Path $here 'Unpin-And-Remove-OEM.ps1'

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
  if ($Apply) { $cArgs += '-Apply' }
  if ($UninstallNotKept) { $cArgs += '-UninstallNotKept' }
  if (-not $Apply -and -not $UninstallNotKept) { $cArgs += '-Audit' }
  Invoke-Step -Path $cleanup -ArgList $cArgs -Label 'Cleanup-Background'
}

if (-not $SkipUnpin -and ($Apply -or $UninstallNotKept)) {
  Invoke-Step -Path $unpin -ArgList @() -Label 'Unpin-And-Remove-OEM'
}

L '==== Admin-Setup finished ===='
Write-Host ''
Write-Host 'Admin-Setup finished. See CSVs/logs under this scripts folder.'
Write-Host "Log: $log"

if ($Restart) {
  L 'Restart requested - 60s'
  shutdown.exe /r /t 60 /c 'Admin-Setup: restart to finish applying changes'
} elseif ($RestartIfNeeded) {
  L 'RestartIfNeeded: rely on child scripts if they scheduled shutdown; otherwise reboot manually if taskbar/apps look stale'
}
