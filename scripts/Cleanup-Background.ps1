<#
.SYNOPSIS
  Audit and clean unnecessary background/startup programs on a Windows PC.

.DESCRIPTION
  Targets third-party auto-start services, Run-key startups, and common junk
  scheduled tasks. Never disables Defender, SecurityHealth, or core Windows.

  -Audit   Report only (default)
  -Apply   Disable/stop listed junk (needs elevation for services/HKLM)
  -WhatIf  With -Apply: show planned changes

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Cleanup-Background.ps1 -Audit
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Cleanup-Background.ps1 -Apply
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [switch]$Audit,
  [switch]$Apply,
  [string]$LogPath = "$env:USERPROFILE\admin\scripts\Cleanup-Background.log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
if (-not $Audit -and -not $Apply) { $Audit = $true }
if ($Apply -and $Audit) { $Audit = $false }

function Write-Log {
  param([string]$Message, [string]$Level = 'INFO')
  $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level, $Message
  New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null
  $line | Tee-Object -FilePath $LogPath -Append
}

function Test-IsAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Add-Result {
  param([string]$Item, [string]$Status, [string]$Detail)
  [pscustomobject]@{ Item = $Item; Status = $Status; Detail = $Detail }
}

$results = New-Object System.Collections.Generic.List[object]
Write-Log "==== Start mode=$(if($Apply){'Apply'}else{'Audit'}) elevated=$(Test-IsAdmin) ===="

if ($Apply -and -not (Test-IsAdmin)) {
  Write-Log 'Re-launching elevated...' 'WARN'
  Start-Process powershell.exe -Verb RunAs -ArgumentList @(
    '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"","-Apply"
  ) | Out-Null
  return
}

# --- Known junk / optional gaming/vendor services (safe to disable for general use) ---
$junkServices = @(
  'CortexLauncherService',           # Razer Cortex
  'Razer Game Manager Service 3',
  'Razer Update Service',
  'RzActionSvc',                     # Razer Central
  'IJPLMSVC',                        # Canon survey
  'AdobeARMservice',
  'AdobeUpdateService',
  'GoogleUpdaterInternalService*',
  'GoogleUpdaterService*',
  'gupdate',
  'gupdatem',
  'EdgeUpdate',
  'MicrosoftEdgeElevationService',
  'Steam Client Service',
  'Origin Client Service',
  'Origin Web Helper Service',
  'EpicOnlineServices',
  'ClickToRunSvc'                    # leave Office alone by default - REMOVE from list
)

# Do NOT touch Office Click-to-Run by default
$junkServices = $junkServices | Where-Object { $_ -ne 'ClickToRunSvc' }

# Never touch these
$neverTouch = @(
  'WinDefend','MDCoreSvc','Sense','WdNisSvc','SecurityHealthService',
  'wuauserv','BITS','Dhcp','Dnscache','EventLog','RpcSs','Schedule',
  'Winmgmt','AudioSrv','Audiosrv','BrokerInfrastructure','SystemEventsBroker',
  'DcomLaunch','LSM','Power','ProfSvc','SamSs','Themes','UserManager',
  'VaultSvc','WlanSvc','Netman','NlaSvc','nsi','mpssvc','BFE','StateRepository',
  'AppXSvc','camsvc','CoreMessagingRegistrar','FontCache','FontCache3.0.0.0'
)

foreach ($pattern in $junkServices) {
  $svcs = @(Get-Service -Name $pattern -ErrorAction SilentlyContinue)
  foreach ($svc in $svcs) {
    if ($neverTouch -contains $svc.Name) { continue }
    $detail = "Status=$($svc.Status) StartType=$($svc.StartType) Display=$($svc.DisplayName)"
    if ($svc.StartType -eq 'Disabled' -and $svc.Status -ne 'Running') {
      $results.Add((Add-Result "Service $($svc.Name)" 'OK' $detail))
      continue
    }
    if ($Apply -and $PSCmdlet.ShouldProcess($svc.Name, 'Stop and Disable')) {
      try {
        if ($svc.Status -eq 'Running') { Stop-Service -Name $svc.Name -Force -ErrorAction Stop }
        Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction Stop
        $results.Add((Add-Result "Service $($svc.Name)" 'FIXED' "stopped+Disabled ($($svc.DisplayName))"))
      } catch {
        $results.Add((Add-Result "Service $($svc.Name)" 'NEED' $_.Exception.Message))
      }
    } else {
      $results.Add((Add-Result "Service $($svc.Name)" 'NEED' $detail))
    }
  }
}

# --- Run key startups to remove (user + machine) ---
$runJunkNames = @(
  'MicrosoftEdgeAutoLaunch_*',
  'Electron',
  'Discord',
  'Steam',
  'EpicGamesLauncher',
  'Adobe*',
  'iTunesHelper',
  'Spotify',
  'Skype*',
  'ccleaner*',
  'Razer*',
  'Cortex*',
  'Teams*',
  'com.squirrel.*'
)

$runPaths = @(
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
)

foreach ($rk in $runPaths) {
  if (-not (Test-Path $rk)) { continue }
  $props = Get-ItemProperty -Path $rk -ErrorAction SilentlyContinue
  if (-not $props) { continue }
  $names = $props.PSObject.Properties | Where-Object {
    $_.Name -notin @('PSPath','PSParentPath','PSChildName','PSDrive','PSProvider')
  }
  foreach ($n in $names) {
    $isJunk = $false
    foreach ($pat in $runJunkNames) {
      if ($n.Name -like $pat) { $isJunk = $true; break }
    }
    # Also flag Edge auto-launch by command line
    if ($n.Value -match 'msedge\.exe.*--win-session-start') { $isJunk = $true }
    if ($n.Name -eq 'SecurityHealth') { continue }
    if (-not $isJunk) {
      $results.Add((Add-Result "Startup keep $($n.Name)" 'OK' "$rk => $($n.Value)"))
      continue
    }
    if ($Apply -and $PSCmdlet.ShouldProcess("$rk\$($n.Name)", 'Remove Run entry')) {
      try {
        Remove-ItemProperty -Path $rk -Name $n.Name -Force -ErrorAction Stop
        $results.Add((Add-Result "Startup $($n.Name)" 'FIXED' "removed from $rk"))
      } catch {
        $results.Add((Add-Result "Startup $($n.Name)" 'NEED' $_.Exception.Message))
      }
    } else {
      $results.Add((Add-Result "Startup $($n.Name)" 'NEED' "$rk => $($n.Value)"))
    }
  }
}

# --- Startup folder shortcuts ---
$startupDirs = @(
  [Environment]::GetFolderPath('Startup'),
  "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
)
foreach ($dir in $startupDirs) {
  if (-not (Test-Path $dir)) { continue }
  Get-ChildItem $dir -Force -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -match 'desktop\.ini') { return }
    $item = $_
    if ($Apply -and $PSCmdlet.ShouldProcess($item.FullName, 'Remove startup shortcut')) {
      try {
        Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
        $results.Add((Add-Result "StartupFolder $($item.Name)" 'FIXED' "removed $($item.FullName)"))
      } catch {
        $results.Add((Add-Result "StartupFolder $($item.Name)" 'NEED' $_.Exception.Message))
      }
    } else {
      $results.Add((Add-Result "StartupFolder $($item.Name)" 'NEED' $item.FullName))
    }
  }
}

# --- Scheduled tasks often used for updaters / surveys ---
$taskPatterns = @(
  '\Razer\*',
  '\Adobe*\*',
  '\Google\*',
  '\Microsoft\EdgeUpdate\*',
  '\Canon*\*'
)
foreach ($tp in $taskPatterns) {
  try {
    $tasks = @(Get-ScheduledTask -TaskPath $tp -ErrorAction SilentlyContinue | Where-Object { $_.State -ne 'Disabled' })
  } catch { $tasks = @() }
  foreach ($t in $tasks) {
    $id = "$($t.TaskPath)$($t.TaskName)"
    if ($Apply -and $PSCmdlet.ShouldProcess($id, 'Disable scheduled task')) {
      try {
        Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Stop | Out-Null
        $results.Add((Add-Result "Task $id" 'FIXED' "disabled (was $($t.State))"))
      } catch {
        $results.Add((Add-Result "Task $id" 'NEED' $_.Exception.Message))
      }
    } else {
      $results.Add((Add-Result "Task $id" 'NEED' "State=$($t.State)"))
    }
  }
}

# --- Disable Windows "Let apps run in background" (best-effort HKCU) ---
$bgPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'
if (-not (Test-Path $bgPath)) { New-Item -Path $bgPath -Force | Out-Null }
$globalBg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
# Global background apps policy (Windows 10/11)
$bgPolicy = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'
$cur = $null
try { $cur = (Get-ItemProperty -Path $bgPolicy -Name 'GlobalUserDisabled' -ErrorAction Stop).GlobalUserDisabled } catch {}
if ($cur -eq 1) {
  $results.Add((Add-Result 'Background apps global' 'OK' 'GlobalUserDisabled=1'))
} elseif ($Apply) {
  New-ItemProperty -Path $bgPolicy -Name 'GlobalUserDisabled' -Value 1 -PropertyType DWord -Force | Out-Null
  $results.Add((Add-Result 'Background apps global' 'FIXED' 'GlobalUserDisabled=1'))
} else {
  $results.Add((Add-Result 'Background apps global' 'NEED' "want 1; have $cur"))
}

# --- Report heavy non-essential processes (info only; do not kill user apps) ---
$heavy = Get-Process -ErrorAction SilentlyContinue |
  Where-Object { $_.ProcessName -match '^(Razer|Cortex|Adobe|CCXProcess|Creative Cloud|iTunesHelper|Spotify|Discord|Steam|EpicGames|PhoneExperienceHost|LinkedIn|M365Copilot)$' } |
  Select-Object ProcessName,Id,@{n='MB';e={[math]::Round($_.WorkingSet64/1MB,1)}}
if ($heavy) {
  foreach ($h in $heavy) {
    if ($Apply -and $h.ProcessName -match '^(Razer|Cortex|Adobe|CCXProcess)') {
      try {
        Stop-Process -Id $h.Id -Force -ErrorAction Stop
        $results.Add((Add-Result "Process $($h.ProcessName)" 'FIXED' "killed pid=$($h.Id) ~$($h.MB)MB"))
      } catch {
        $results.Add((Add-Result "Process $($h.ProcessName)" 'NEED' $_.Exception.Message))
      }
    } else {
      $results.Add((Add-Result "Process $($h.ProcessName)" $(if($Apply){'OK'}else{'NEED'}) "pid=$($h.Id) ~$($h.MB)MB (running)"))
    }
  }
} else {
  $results.Add((Add-Result 'Heavy vendor processes' 'OK' 'none matched'))
}

# --- Summary ---
$ok = @($results | Where-Object Status -eq 'OK').Count
$need = @($results | Where-Object Status -eq 'NEED').Count
$fixed = @($results | Where-Object Status -eq 'FIXED').Count
Write-Log "Summary OK=$ok FIXED=$fixed NEED=$need"
$csv = [IO.Path]::ChangeExtension($LogPath, '.csv')
$results | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
Write-Log "CSV: $csv"
Write-Host ""
Write-Host "Cleanup-Background complete  OK=$ok  FIXED=$fixed  NEED=$need"
Write-Host "Log: $LogPath"
Write-Host "CSV: $csv"
if (-not $Apply) {
  Write-Host "Re-run elevated with -Apply to disable listed junk services/startups."
}
