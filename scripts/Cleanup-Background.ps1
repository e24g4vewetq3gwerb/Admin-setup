<#
.SYNOPSIS
  Cleanup background junk and uninstall programs not on the keep list.

.DESCRIPTION
  Keep profile (default Minimal): Google Chrome, Grok / Grok Bot, Windows Terminal.
  Also protects drivers/runtimes required for a usable PC (audio, VC++ redistributables,
  Canon printer drivers). Everything else in the uninstall list is a removal candidate.

  -Audit              List only (default). Always writes program CSVs.
  -Apply              Disable junk services/startups/background apps.
  -UninstallNotKept   Uninstall programs not matching Keep/Protect patterns.
  -Restart            Reboot when finished (after Apply/Uninstall).
  -RestartIfNeeded    Reboot only if uninstall/service changes were made.
  -WhatIf             Show planned changes without making them.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Cleanup-Background.ps1 -Audit
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Cleanup-Background.ps1 -Apply -UninstallNotKept -RestartIfNeeded
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [switch]$Audit,
  [switch]$Apply,
  [switch]$UninstallNotKept,
  [switch]$UninstallJunk,  # alias behavior: same junk patterns; prefer -UninstallNotKept
  [switch]$Restart,
  [switch]$RestartIfNeeded,
  [ValidateSet('Minimal')]
  [string]$KeepProfile = 'Minimal',
  [string]$LogPath = "$env:USERPROFILE\admin\scripts\Cleanup-Background.log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
if (-not $Audit -and -not $Apply -and -not $UninstallNotKept -and -not $UninstallJunk) { $Audit = $true }
if (($Apply -or $UninstallNotKept -or $UninstallJunk) -and $Audit) { $Audit = $false }

$script:ChangesMade = $false

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

function Test-NameMatch {
  param([string]$Name, [string[]]$Patterns)
  foreach ($pat in $Patterns) {
    if ($Name -like $pat) { return $true }
  }
  return $false
}

function Get-Prop {
  param($Object, [string]$Name)
  $p = $Object.PSObject.Properties[$Name]
  if ($p) { return $p.Value }
  return $null
}

function Get-InstalledPrograms {
  $paths = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
  Get-ItemProperty $paths -ErrorAction SilentlyContinue |
    Where-Object {
      $dn = Get-Prop $_ 'DisplayName'
      if ([string]::IsNullOrWhiteSpace($dn)) { return $false }
      $sc = Get-Prop $_ 'SystemComponent'
      if ($null -ne $sc -and [int]$sc -eq 1) { return $false }
      $true
    } |
    ForEach-Object {
      [pscustomobject]@{
        DisplayName          = (Get-Prop $_ 'DisplayName')
        DisplayVersion       = (Get-Prop $_ 'DisplayVersion')
        Publisher            = (Get-Prop $_ 'Publisher')
        InstallDate          = (Get-Prop $_ 'InstallDate')
        EstimatedSizeKB      = (Get-Prop $_ 'EstimatedSize')
        UninstallString      = (Get-Prop $_ 'UninstallString')
        QuietUninstallString = (Get-Prop $_ 'QuietUninstallString')
        PSChildName          = (Get-Prop $_ 'PSChildName')
        HivePath             = (Get-Prop $_ 'PSPath')
      }
    } |
    Sort-Object DisplayName -Unique
}

function Invoke-QuietUninstall {
  param($Program)
  $u = $Program.QuietUninstallString
  if (-not $u) { $u = $Program.UninstallString }
  if (-not $u) { throw 'No uninstall string' }

  if ($u -match 'MsiExec\.exe[^\dA-Fa-f-]*\{([0-9A-Fa-f-]+)\}' -or $u -match '\{([0-9A-Fa-f-]{36})\}') {
    $guid = $Matches[1]
    $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/X{$guid}","/qn","/norestart" -Wait -PassThru
    if ($p.ExitCode -notin 0,3010) { throw "msiexec exit $($p.ExitCode)" }
    if ($p.ExitCode -eq 3010) { $script:ChangesMade = $true }
    return $p.ExitCode
  }
  if ($Program.QuietUninstallString) {
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $Program.QuietUninstallString -Wait -PassThru -WindowStyle Hidden
    if ($p.ExitCode -notin 0,3010) { throw "quiet exit $($p.ExitCode)" }
    return $p.ExitCode
  }
  if ($u -match '^"([^"]+)"\s*(.*)$') {
    $exe = $Matches[1]; $rest = ($Matches[2] + ' /S /quiet /qn /norestart').Trim()
    $p = Start-Process -FilePath $exe -ArgumentList $rest -Wait -PassThru
    if ($p.ExitCode -notin 0,3010) { throw "exit $($p.ExitCode)" }
    return $p.ExitCode
  }
  throw "Unsupported uninstall string: $u"
}

$results = New-Object System.Collections.Generic.List[object]
$logDir = Split-Path $LogPath
Write-Log "==== Start KeepProfile=$KeepProfile Apply=$Apply UninstallNotKept=$UninstallNotKept Restart=$Restart RestartIfNeeded=$RestartIfNeeded elevated=$(Test-IsAdmin) ===="

if (($Apply -or $UninstallNotKept -or $UninstallJunk) -and -not (Test-IsAdmin)) {
  Write-Log 'Re-launching elevated...' 'WARN'
  $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
  if ($Apply) { $argList += '-Apply' }
  if ($UninstallNotKept) { $argList += '-UninstallNotKept' }
  if ($UninstallJunk) { $argList += '-UninstallJunk' }
  if ($Restart) { $argList += '-Restart' }
  if ($RestartIfNeeded) { $argList += '-RestartIfNeeded' }
  if ($WhatIfPreference) { $argList += '-WhatIf' }
  Start-Process powershell.exe -Verb RunAs -ArgumentList $argList | Out-Null
  return
}

# --- Keep / protect policy ---
# User-requested keepers
$keepPatterns = @(
  'Google Chrome',
  'Grok',
  'Grok Bot*',
  'Windows Terminal*',
  'Terminal*'
)

# Required for a usable machine (not "apps", but don't strip)
$protectPatterns = @(
  'Realtek*',
  'Microsoft Visual C++*',
  'Microsoft Windows Application Compatibility*',
  'Canon TR*',
  'Canon IJ Printer*',
  'Canon IJ Scan*',
  'Canon IJ Network*',
  'Printer Registration'
)

# Legacy junk patterns (used if -UninstallJunk without -UninstallNotKept)
$junkUninstallPatterns = @(
  'Razer *','Streamer Companion App','THX Spatial Audio',
  'Canon Inkjet Printer/Scanner/Fax Extended Survey Program',
  'Adobe *','McAfee*','Norton*','Avast*','AVG*','CCleaner*',
  'Driver Booster*','iTunes','Skype*','Spotify*','Discord*','Steam*','Epic Games*'
)

$programs = @(Get-InstalledPrograms)
$progCsv = Join-Path $logDir 'Cleanup-Background-Programs.csv'
$programs | Export-Csv -Path $progCsv -NoTypeInformation -Encoding UTF8
Write-Log "Installed programs: $($programs.Count) -> $progCsv"
$results.Add((Add-Result 'Uninstall program list' 'OK' "$($programs.Count) apps -> $progCsv"))

$removeCandidates = @($programs | Where-Object {
  $n = $_.DisplayName
  -not (Test-NameMatch -Name $n -Patterns $keepPatterns) -and
  -not (Test-NameMatch -Name $n -Patterns $protectPatterns)
})

# If only -UninstallJunk (legacy), narrow to junk patterns
if ($UninstallJunk -and -not $UninstallNotKept) {
  $removeCandidates = @($removeCandidates | Where-Object {
    Test-NameMatch -Name $_.DisplayName -Patterns $junkUninstallPatterns
  })
}

$removeCsv = Join-Path $logDir 'Cleanup-Background-RemoveCandidates.csv'
$removeCandidates | Export-Csv -Path $removeCsv -NoTypeInformation -Encoding UTF8
Write-Log "Remove candidates: $($removeCandidates.Count) -> $removeCsv"

$kept = @($programs | Where-Object {
  (Test-NameMatch -Name $_.DisplayName -Patterns $keepPatterns) -or
  (Test-NameMatch -Name $_.DisplayName -Patterns $protectPatterns)
})
$keptCsv = Join-Path $logDir 'Cleanup-Background-KeepList.csv'
$kept | Export-Csv -Path $keptCsv -NoTypeInformation -Encoding UTF8

foreach ($k in $kept) {
  $results.Add((Add-Result "KEEP $($k.DisplayName)" 'OK' "Publisher=$($k.Publisher)"))
}

foreach ($j in $removeCandidates) {
  $u = if ($j.QuietUninstallString) { $j.QuietUninstallString } else { $j.UninstallString }
  $doUninstall = $UninstallNotKept -or $UninstallJunk
  if ($doUninstall -and $u) {
    if ($PSCmdlet.ShouldProcess($j.DisplayName, 'Quiet uninstall')) {
      try {
        $code = Invoke-QuietUninstall -Program $j
        $script:ChangesMade = $true
        $results.Add((Add-Result "Uninstall $($j.DisplayName)" 'FIXED' "exit=$code"))
      } catch {
        $results.Add((Add-Result "Uninstall $($j.DisplayName)" 'NEED' $_.Exception.Message))
      }
    }
  } else {
    $results.Add((Add-Result "REMOVE candidate $($j.DisplayName)" 'NEED' "Publisher=$($j.Publisher); Uninstall=$u"))
  }
}

if ($removeCandidates.Count -eq 0) {
  $results.Add((Add-Result 'Remove candidates' 'OK' 'none'))
}

# --- Store / AppX optional apps (best-effort; skip system) ---
$appxJunk = @(
  'Microsoft.BingNews','Microsoft.BingWeather','Microsoft.GetHelp','Microsoft.Getstarted',
  'Microsoft.MicrosoftSolitaireCollection','Microsoft.People','Microsoft.SkypeApp',
  'Microsoft.WindowsMaps','Microsoft.Xbox.TCUI','Microsoft.XboxApp','Microsoft.XboxGameOverlay',
  'Microsoft.XboxGamingOverlay','Microsoft.XboxIdentityProvider','Microsoft.XboxSpeechToTextOverlay',
  'Microsoft.YourPhone','Microsoft.ZuneMusic','Microsoft.ZuneVideo','microsoft.windowscommunicationsapps',
  'Disney.37853FC22B2CE','SpotifyAB.SpotifyMusic','Facebook.Facebook*','LinkedIn*'
)
if ($Apply -or $UninstallNotKept) {
  foreach ($ax in $appxJunk) {
    $pkgs = @(Get-AppxPackage -Name $ax -ErrorAction SilentlyContinue)
    foreach ($pkg in $pkgs) {
      if ($PSCmdlet.ShouldProcess($pkg.Name, 'Remove-AppxPackage')) {
        try {
          Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
          $script:ChangesMade = $true
          $results.Add((Add-Result "AppX $($pkg.Name)" 'FIXED' 'removed for current user'))
        } catch {
          $results.Add((Add-Result "AppX $($pkg.Name)" 'NEED' $_.Exception.Message))
        }
      }
    }
  }
}

# --- Services ---
$junkServices = @(
  'CortexLauncherService','Razer Game Manager Service 3','Razer Update Service','RzActionSvc',
  'IJPLMSVC','AdobeARMservice','AdobeUpdateService','GoogleUpdaterInternalService*',
  'GoogleUpdaterService*','gupdate','gupdatem','EdgeUpdate','MicrosoftEdgeElevationService',
  'Steam Client Service','Origin Client Service','Origin Web Helper Service','EpicOnlineServices'
)
$neverTouch = @(
  'WinDefend','MDCoreSvc','Sense','WdNisSvc','SecurityHealthService','wuauserv','BITS','Dhcp',
  'Dnscache','EventLog','RpcSs','Schedule','Winmgmt','AudioSrv','Audiosrv','BrokerInfrastructure',
  'SystemEventsBroker','DcomLaunch','LSM','Power','ProfSvc','SamSs','Themes','UserManager',
  'VaultSvc','WlanSvc','Netman','NlaSvc','nsi','mpssvc','BFE','StateRepository','AppXSvc','camsvc',
  'CoreMessagingRegistrar','FontCache'
)
foreach ($pattern in $junkServices) {
  foreach ($svc in @(Get-Service -Name $pattern -ErrorAction SilentlyContinue)) {
    if ($neverTouch -contains $svc.Name) { continue }
    $detail = "Status=$($svc.Status) StartType=$($svc.StartType)"
    if ($svc.StartType -eq 'Disabled' -and $svc.Status -ne 'Running') {
      $results.Add((Add-Result "Service $($svc.Name)" 'OK' $detail)); continue
    }
    if ($Apply -and $PSCmdlet.ShouldProcess($svc.Name, 'Stop and Disable')) {
      try {
        if ($svc.Status -eq 'Running') { Stop-Service -Name $svc.Name -Force -ErrorAction Stop }
        Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction Stop
        $script:ChangesMade = $true
        $results.Add((Add-Result "Service $($svc.Name)" 'FIXED' "stopped+Disabled ($($svc.DisplayName))"))
      } catch {
        $results.Add((Add-Result "Service $($svc.Name)" 'NEED' $_.Exception.Message))
      }
    } else {
      $results.Add((Add-Result "Service $($svc.Name)" 'NEED' $detail))
    }
  }
}

# --- Run keys ---
$runJunkNames = @(
  'MicrosoftEdgeAutoLaunch_*','Electron','Discord','Steam','EpicGamesLauncher','Adobe*',
  'iTunesHelper','Spotify','Skype*','ccleaner*','Razer*','Cortex*','Teams*','com.squirrel.*',
  'Copilot*','Microsoft.Teams*','OneDrive*'
)
foreach ($rk in @(
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
)) {
  if (-not (Test-Path $rk)) { continue }
  $props = Get-ItemProperty -Path $rk -ErrorAction SilentlyContinue
  if (-not $props) { continue }
  foreach ($n in @($props.PSObject.Properties | Where-Object { $_.Name -notin @('PSPath','PSParentPath','PSChildName','PSDrive','PSProvider') })) {
    if ($n.Name -eq 'SecurityHealth') { continue }
    $isJunk = $false
    foreach ($pat in $runJunkNames) { if ($n.Name -like $pat) { $isJunk = $true; break } }
    if ($n.Value -match 'msedge\.exe.*--win-session-start') { $isJunk = $true }
    # Never remove Chrome / Grok startup if present
    if ($n.Value -match 'chrome\.exe' -or $n.Value -match 'Grok' -or $n.Name -match 'Grok') {
      $results.Add((Add-Result "Startup keep $($n.Name)" 'OK' "$rk => $($n.Value)"))
      continue
    }
    if (-not $isJunk) {
      $results.Add((Add-Result "Startup other $($n.Name)" 'NEED' "$rk => $($n.Value)"))
      if ($Apply -and $UninstallNotKept -and $PSCmdlet.ShouldProcess("$rk\$($n.Name)", 'Remove non-keep Run entry')) {
        try {
          Remove-ItemProperty -Path $rk -Name $n.Name -Force -ErrorAction Stop
          $script:ChangesMade = $true
          $results.Add((Add-Result "Startup $($n.Name)" 'FIXED' "removed from $rk"))
        } catch {
          $results.Add((Add-Result "Startup $($n.Name)" 'NEED' $_.Exception.Message))
        }
      }
      continue
    }
    if ($Apply -and $PSCmdlet.ShouldProcess("$rk\$($n.Name)", 'Remove Run entry')) {
      try {
        Remove-ItemProperty -Path $rk -Name $n.Name -Force -ErrorAction Stop
        $script:ChangesMade = $true
        $results.Add((Add-Result "Startup $($n.Name)" 'FIXED' "removed from $rk"))
      } catch {
        $results.Add((Add-Result "Startup $($n.Name)" 'NEED' $_.Exception.Message))
      }
    } else {
      $results.Add((Add-Result "Startup $($n.Name)" 'NEED' "$rk => $($n.Value)"))
    }
  }
}

# --- Startup folders ---
foreach ($dir in @([Environment]::GetFolderPath('Startup'), "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup")) {
  if (-not (Test-Path $dir)) { continue }
  Get-ChildItem $dir -Force -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -match 'desktop\.ini') { return }
    if ($_.Name -match 'Chrome|Grok|Terminal') {
      $results.Add((Add-Result "StartupFolder keep $($_.Name)" 'OK' $_.FullName))
      return
    }
    if ($Apply -and $PSCmdlet.ShouldProcess($_.FullName, 'Remove startup shortcut')) {
      try {
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
        $script:ChangesMade = $true
        $results.Add((Add-Result "StartupFolder $($_.Name)" 'FIXED' 'removed'))
      } catch {
        $results.Add((Add-Result "StartupFolder $($_.Name)" 'NEED' $_.Exception.Message))
      }
    } else {
      $results.Add((Add-Result "StartupFolder $($_.Name)" 'NEED' $_.FullName))
    }
  }
}

# --- Scheduled tasks ---
foreach ($tp in @('\Razer\*','\Adobe*\*','\Google\*','\Microsoft\EdgeUpdate\*','\Canon*\*')) {
  try { $tasks = @(Get-ScheduledTask -TaskPath $tp -ErrorAction SilentlyContinue | Where-Object { $_.State -ne 'Disabled' }) }
  catch { $tasks = @() }
  foreach ($t in $tasks) {
    $id = "$($t.TaskPath)$($t.TaskName)"
    if ($Apply -and $PSCmdlet.ShouldProcess($id, 'Disable scheduled task')) {
      try {
        Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Stop | Out-Null
        $script:ChangesMade = $true
        $results.Add((Add-Result "Task $id" 'FIXED' "disabled"))
      } catch {
        $results.Add((Add-Result "Task $id" 'NEED' $_.Exception.Message))
      }
    } else {
      $results.Add((Add-Result "Task $id" 'NEED' "State=$($t.State)"))
    }
  }
}

# --- Background apps ---
$bgPolicy = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'
if (-not (Test-Path $bgPolicy)) { New-Item -Path $bgPolicy -Force | Out-Null }
$cur = $null
try { $cur = (Get-ItemProperty -Path $bgPolicy -Name 'GlobalUserDisabled' -ErrorAction Stop).GlobalUserDisabled } catch {}
if ($cur -eq 1) {
  $results.Add((Add-Result 'Background apps global' 'OK' 'GlobalUserDisabled=1'))
} elseif ($Apply) {
  New-ItemProperty -Path $bgPolicy -Name 'GlobalUserDisabled' -Value 1 -PropertyType DWord -Force | Out-Null
  $script:ChangesMade = $true
  $results.Add((Add-Result 'Background apps global' 'FIXED' 'GlobalUserDisabled=1'))
} else {
  $results.Add((Add-Result 'Background apps global' 'NEED' "want 1; have $cur"))
}

# --- Kill leftover vendor processes ---
$heavy = Get-Process -ErrorAction SilentlyContinue |
  Where-Object { $_.ProcessName -match '^(Razer|Cortex|Adobe|CCXProcess|Spotify|Discord|Steam|EpicGames|Copilot|PhoneExperienceHost|LinkedIn)$' }
foreach ($h in @($heavy)) {
  if ($Apply) {
    try {
      Stop-Process -Id $h.Id -Force -ErrorAction Stop
      $script:ChangesMade = $true
      $results.Add((Add-Result "Process $($h.ProcessName)" 'FIXED' "killed pid=$($h.Id)"))
    } catch {
      $results.Add((Add-Result "Process $($h.ProcessName)" 'NEED' $_.Exception.Message))
    }
  } else {
    $results.Add((Add-Result "Process $($h.ProcessName)" 'NEED' "pid=$($h.Id) running"))
  }
}

# --- Summary ---
$ok = @($results | Where-Object Status -eq 'OK').Count
$need = @($results | Where-Object Status -eq 'NEED').Count
$fixed = @($results | Where-Object Status -eq 'FIXED').Count
Write-Log "Summary OK=$ok FIXED=$fixed NEED=$need ChangesMade=$script:ChangesMade"
$csv = [IO.Path]::ChangeExtension($LogPath, '.csv')
$results | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
Write-Host ""
Write-Host "Cleanup-Background complete  OK=$ok  FIXED=$fixed  NEED=$need"
Write-Host "Keep list:     $keptCsv ($($kept.Count))"
Write-Host "Programs:      $progCsv ($($programs.Count))"
Write-Host "Remove list:   $removeCsv ($($removeCandidates.Count))"
Write-Host "Results:       $csv"
Write-Host "Log:           $LogPath"
if (-not $Apply -and -not $UninstallNotKept -and -not $UninstallJunk) {
  Write-Host "To apply: -Apply -UninstallNotKept [-RestartIfNeeded|-Restart]"
}

# --- Restart policy ---
$shouldRestart = $false
if ($Restart) { $shouldRestart = $true }
elseif ($RestartIfNeeded -and $script:ChangesMade) { $shouldRestart = $true }

if ($shouldRestart) {
  Write-Log 'Restart requested — rebooting in 60 seconds (shutdown /a to cancel)' 'WARN'
  Write-Host "Restarting in 60 seconds to finish applying changes. Run: shutdown /a   to cancel."
  shutdown.exe /r /t 60 /c "Cleanup-Background: restart to finish applying changes"
} elseif ($RestartIfNeeded -and -not $script:ChangesMade) {
  Write-Log 'RestartIfNeeded set but no changes made — skip reboot'
  Write-Host 'No changes that need a restart.'
}
