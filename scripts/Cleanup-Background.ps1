<#
.SYNOPSIS
  Audit and clean unnecessary background/startup programs on a Windows PC.

.DESCRIPTION
  Targets third-party auto-start services, Run-key startups, scheduled tasks,
  and exports the full uninstall program list. Never disables Defender,
  SecurityHealth, or core Windows.

  -Audit         Report only (default)
  -Apply         Disable/stop listed junk services/startups (needs elevation)
  -UninstallJunk Quiet-uninstall programs matching the junk name list (opt-in;
                 requires -Apply or can be used alone; needs elevation)
  -WhatIf        With -Apply/-UninstallJunk: show planned changes

  Always writes:
    Cleanup-Background-Programs.csv   full installed program list
    Cleanup-Background-JunkCandidates.csv   programs matching junk patterns

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Cleanup-Background.ps1 -Audit
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Cleanup-Background.ps1 -Apply
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Cleanup-Background.ps1 -Apply -UninstallJunk
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [switch]$Audit,
  [switch]$Apply,
  [switch]$UninstallJunk,
  [string]$LogPath = "$env:USERPROFILE\admin\scripts\Cleanup-Background.log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
if (-not $Audit -and -not $Apply -and -not $UninstallJunk) { $Audit = $true }
if (($Apply -or $UninstallJunk) -and $Audit) { $Audit = $false }

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

function Get-InstalledPrograms {
  $paths = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
  Get-ItemProperty $paths -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
    ForEach-Object {
      [pscustomobject]@{
        DisplayName          = $_.DisplayName
        DisplayVersion       = $_.DisplayVersion
        Publisher            = $_.Publisher
        InstallDate          = $_.InstallDate
        EstimatedSizeKB      = $_.EstimatedSize
        UninstallString      = $_.UninstallString
        QuietUninstallString = $_.QuietUninstallString
        PSChildName          = $_.PSChildName
        HivePath             = $_.PSPath
      }
    } |
    Sort-Object DisplayName -Unique
}

$results = New-Object System.Collections.Generic.List[object]
$logDir = Split-Path $LogPath
Write-Log "==== Start mode=$(if($UninstallJunk){'UninstallJunk/'})$(if($Apply){'Apply'}elseif(-not $UninstallJunk){'Audit'}) elevated=$(Test-IsAdmin) ===="

if (($Apply -or $UninstallJunk) -and -not (Test-IsAdmin)) {
  Write-Log 'Re-launching elevated...' 'WARN'
  $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
  if ($Apply) { $argList += '-Apply' }
  if ($UninstallJunk) { $argList += '-UninstallJunk' }
  if ($WhatIfPreference) { $argList += '-WhatIf' }
  Start-Process powershell.exe -Verb RunAs -ArgumentList $argList | Out-Null
  return
}

# ========== Installed program / uninstall list ==========
# Patterns treated as junk uninstall candidates (name match)
$junkUninstallPatterns = @(
  'Razer Cortex',
  'Razer Axon',
  'Razer Chroma',
  'Razer Synapse',
  'Razer Virtual Ring Light',
  'Streamer Companion App',
  'THX Spatial Audio',
  'Canon Inkjet Printer/Scanner/Fax Extended Survey Program',
  'Adobe Creative Cloud',
  'Adobe Acrobat*',
  'McAfee*',
  'Norton*',
  'Avast*',
  'AVG*',
  'CCleaner*',
  'Driver Booster*',
  'iTunes',
  'Apple Software Update',
  'Bonjour',
  'Skype*',
  'Spotify*',
  'Discord*',
  'Steam*',
  'Epic Games*',
  'Origin*',
  'Battle.net*'
)

# Never auto-uninstall these even if pattern somehow matches
$neverUninstall = @(
  'Google Chrome',
  'Microsoft Edge',
  'Grok Bot*',
  'Grok',
  'Cursor*',
  'Git',
  'GitHub CLI',
  'Node.js',
  'Python*',
  'Microsoft Visual C++*',
  'Windows SDK*',
  'Visual Studio*',
  'Realtek*',
  'Canon TR*',
  'Canon IJ Printer*',
  'Canon IJ Scan*',
  'Canon IJ Network*',
  'Printer Registration',
  'FFmpeg',
  'Copilot'
)

$programs = @(Get-InstalledPrograms)
$progCsv = Join-Path $logDir 'Cleanup-Background-Programs.csv'
$programs | Export-Csv -Path $progCsv -NoTypeInformation -Encoding UTF8
Write-Log "Installed programs listed: $($programs.Count) -> $progCsv"
$results.Add((Add-Result 'Uninstall program list' 'OK' "$($programs.Count) apps exported to $progCsv"))

function Test-NameMatch {
  param([string]$Name, [string[]]$Patterns)
  foreach ($pat in $Patterns) {
    if ($Name -like $pat) { return $true }
  }
  return $false
}

$junkCandidates = @($programs | Where-Object {
  (Test-NameMatch -Name $_.DisplayName -Patterns $junkUninstallPatterns) -and
  -not (Test-NameMatch -Name $_.DisplayName -Patterns $neverUninstall)
})

$junkCsv = Join-Path $logDir 'Cleanup-Background-JunkCandidates.csv'
$junkCandidates | Export-Csv -Path $junkCsv -NoTypeInformation -Encoding UTF8
Write-Log "Junk uninstall candidates: $($junkCandidates.Count) -> $junkCsv"

foreach ($j in $junkCandidates) {
  $u = if ($j.QuietUninstallString) { $j.QuietUninstallString } else { $j.UninstallString }
  if ($UninstallJunk -and $u) {
    if ($PSCmdlet.ShouldProcess($j.DisplayName, "Uninstall via: $u")) {
      try {
        # MSI quiet
        if ($u -match 'MsiExec\.exe\s+/X\{?([0-9A-Fa-f-]+)\}?' -or $u -match 'MsiExec\.exe.*"\{([0-9A-Fa-f-]+)\}"') {
          $guid = $Matches[1]
          $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/X{$guid} /qn /norestart" -Wait -PassThru
          $results.Add((Add-Result "Uninstall $($j.DisplayName)" $(if($p.ExitCode -eq 0){'FIXED'}else{'NEED'}) "msiexec exit=$($p.ExitCode)"))
        } elseif ($j.QuietUninstallString) {
          $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $j.QuietUninstallString -Wait -PassThru -WindowStyle Hidden
          $results.Add((Add-Result "Uninstall $($j.DisplayName)" $(if($p.ExitCode -eq 0){'FIXED'}else{'NEED'}) "quiet exit=$($p.ExitCode)"))
        } else {
          # Best-effort: append quiet flags for common NSIS/Inno
          $cmd = $j.UninstallString
          if ($cmd -match '^"([^"]+)"\s*(.*)$') {
            $exe = $Matches[1]; $rest = $Matches[2]
            $p = Start-Process -FilePath $exe -ArgumentList ($rest + ' /S /quiet /qn').Trim() -Wait -PassThru -ErrorAction Stop
            $results.Add((Add-Result "Uninstall $($j.DisplayName)" $(if($p.ExitCode -eq 0){'FIXED'}else{'NEED'}) "exit=$($p.ExitCode)"))
          } else {
            $results.Add((Add-Result "Uninstall $($j.DisplayName)" 'NEED' "manual uninstall string: $u"))
          }
        }
      } catch {
        $results.Add((Add-Result "Uninstall $($j.DisplayName)" 'NEED' $_.Exception.Message))
      }
    }
  } else {
    $results.Add((Add-Result "Junk candidate $($j.DisplayName)" 'NEED' "Publisher=$($j.Publisher); Uninstall=$u"))
  }
}

if ($junkCandidates.Count -eq 0) {
  $results.Add((Add-Result 'Junk uninstall candidates' 'OK' 'none matched'))
}

# ========== Services ==========
$junkServices = @(
  'CortexLauncherService',
  'Razer Game Manager Service 3',
  'Razer Update Service',
  'RzActionSvc',
  'IJPLMSVC',
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
  'EpicOnlineServices'
)

$neverTouch = @(
  'WinDefend','MDCoreSvc','Sense','WdNisSvc','SecurityHealthService',
  'wuauserv','BITS','Dhcp','Dnscache','EventLog','RpcSs','Schedule',
  'Winmgmt','AudioSrv','Audiosrv','BrokerInfrastructure','SystemEventsBroker',
  'DcomLaunch','LSM','Power','ProfSvc','SamSs','Themes','UserManager',
  'VaultSvc','WlanSvc','Netman','NlaSvc','nsi','mpssvc','BFE','StateRepository',
  'AppXSvc','camsvc','CoreMessagingRegistrar','FontCache'
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

# ========== Run keys ==========
$runJunkNames = @(
  'MicrosoftEdgeAutoLaunch_*','Electron','Discord','Steam','EpicGamesLauncher',
  'Adobe*','iTunesHelper','Spotify','Skype*','ccleaner*','Razer*','Cortex*',
  'Teams*','com.squirrel.*'
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
    foreach ($pat in $runJunkNames) { if ($n.Name -like $pat) { $isJunk = $true; break } }
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

# ========== Startup folders ==========
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

# ========== Scheduled tasks ==========
$taskPatterns = @('\Razer\*','\Adobe*\*','\Google\*','\Microsoft\EdgeUpdate\*','\Canon*\*')
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

# ========== Background apps ==========
$bgPolicy = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'
if (-not (Test-Path $bgPolicy)) { New-Item -Path $bgPolicy -Force | Out-Null }
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

# ========== Heavy vendor processes ==========
$heavy = Get-Process -ErrorAction SilentlyContinue |
  Where-Object { $_.ProcessName -match '^(Razer|Cortex|Adobe|CCXProcess|Creative Cloud|iTunesHelper|Spotify|Discord|Steam|EpicGames)$' } |
  Select-Object ProcessName,Id,@{n='MB';e={[math]::Round($_.WorkingSet64/1MB,1)}}
if ($heavy) {
  foreach ($h in $heavy) {
    if ($Apply) {
      try {
        Stop-Process -Id $h.Id -Force -ErrorAction Stop
        $results.Add((Add-Result "Process $($h.ProcessName)" 'FIXED' "killed pid=$($h.Id) ~$($h.MB)MB"))
      } catch {
        $results.Add((Add-Result "Process $($h.ProcessName)" 'NEED' $_.Exception.Message))
      }
    } else {
      $results.Add((Add-Result "Process $($h.ProcessName)" 'NEED' "pid=$($h.Id) ~$($h.MB)MB (running)"))
    }
  }
} else {
  $results.Add((Add-Result 'Heavy vendor processes' 'OK' 'none matched'))
}

# ========== Summary ==========
$ok = @($results | Where-Object Status -eq 'OK').Count
$need = @($results | Where-Object Status -eq 'NEED').Count
$fixed = @($results | Where-Object Status -eq 'FIXED').Count
Write-Log "Summary OK=$ok FIXED=$fixed NEED=$need"
$csv = [IO.Path]::ChangeExtension($LogPath, '.csv')
$results | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
Write-Log "CSV: $csv"
Write-Host ""
Write-Host "Cleanup-Background complete  OK=$ok  FIXED=$fixed  NEED=$need"
Write-Host "Programs list: $progCsv ($($programs.Count) apps)"
Write-Host "Junk candidates: $junkCsv ($($junkCandidates.Count))"
Write-Host "Log: $LogPath"
Write-Host "Results: $csv"
if (-not $Apply -and -not $UninstallJunk) {
  Write-Host "Re-run elevated with -Apply to disable junk services/startups."
  Write-Host "Add -UninstallJunk to quietly uninstall junk candidates (Razer suite, surveys, etc.)."
}
