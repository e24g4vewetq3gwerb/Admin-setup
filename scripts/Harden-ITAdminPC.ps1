<#
.SYNOPSIS
  Harden a Windows PC toward an IT-admin / requirement-check baseline.

.DESCRIPTION
  Implements automatable items from the IT admin checklist:
  identity/session locks, firewall, Defender, SMB/AutoPlay, RDP posture,
  network discovery hardening, audit policy basics, Fast Startup, power/sleep,
  telemetry-safe defaults, and optional BitLocker / admin-split steps.

  Modes:
    -Audit   Report pass/fail only (default if neither -Audit nor -Apply)
    -Apply   Make changes (requires elevation)
    -WhatIf  With -Apply: show what would change

  Opt-in risky flags (off by default):
    -EnableBitLocker
    -DisableRDP
    -CreateStandardUser <name>   (creates standard user; does NOT demote you automatically)

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Harden-ITAdminPC.ps1 -Audit
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Harden-ITAdminPC.ps1 -Apply
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Harden-ITAdminPC.ps1 -Apply -EnableBitLocker -DisableRDP
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [switch]$Audit,
  [switch]$Apply,
  [switch]$EnableBitLocker,
  [switch]$DisableRDP,
  [string]$CreateStandardUser = '',
  [int]$LockScreenMinutes = 10,
  [string]$LogPath = "$env:USERPROFILE\admin\scripts\Harden-ITAdminPC.log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

if (-not $Audit -and -not $Apply) { $Audit = $true }
if ($Apply -and $Audit) { $Audit = $false }

function Write-Log {
  param([string]$Message, [string]$Level = 'INFO')
  $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level, $Message
  $line | Tee-Object -FilePath $LogPath -Append
}

function Ensure-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-Reg {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)]$Value,
    [ValidateSet('DWord','String','QWord')]$Type = 'DWord'
  )
  if (-not (Test-Path $Path)) {
    if ($Apply -and $PSCmdlet.ShouldProcess($Path, 'New-Item')) {
      New-Item -Path $Path -Force | Out-Null
    }
  }
  $current = $null
  try { $current = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch {}
  $same = ($null -ne $current -and "$current" -eq "$Value")
  if ($same) {
    return [pscustomobject]@{ Item = "$Path::$Name"; Status = 'OK'; Detail = "already $Value" }
  }
  if ($Apply -and $PSCmdlet.ShouldProcess("$Path\$Name", "Set to $Value")) {
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    return [pscustomobject]@{ Item = "$Path::$Name"; Status = 'FIXED'; Detail = "$current -> $Value" }
  }
  return [pscustomobject]@{ Item = "$Path::$Name"; Status = 'NEED'; Detail = "want $Value; have $current" }
}

function Get-Status {
  param([string]$Item, [bool]$Ok, [string]$Detail)
  [pscustomobject]@{
    Item   = $Item
    Status = $(if ($Ok) { 'OK' } else { 'NEED' })
    Detail = $Detail
  }
}

$results = New-Object System.Collections.Generic.List[object]
New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null
Write-Log "==== Start mode=$(if($Apply){'Apply'}else{'Audit'}) elevated=$(Ensure-Admin) user=$env:USERNAME ===="

if ($Apply -and -not (Ensure-Admin)) {
  Write-Log 'Re-launching elevated...' 'WARN'
  $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Apply')
  if ($EnableBitLocker) { $args += '-EnableBitLocker' }
  if ($DisableRDP) { $args += '-DisableRDP' }
  if ($CreateStandardUser) { $args += @('-CreateStandardUser', $CreateStandardUser) }
  if ($WhatIfPreference) { $args += '-WhatIf' }
  Start-Process powershell.exe -Verb RunAs -ArgumentList $args | Out-Null
  return
}

# ---------- 1) Firmware / platform (check only) ----------
try {
  $secureBoot = Confirm-SecureBootUEFI -ErrorAction Stop
  $results.Add((Get-Status 'Secure Boot' $secureBoot "SecureBoot=$secureBoot"))
} catch {
  $results.Add((Get-Status 'Secure Boot' $false $_.Exception.Message))
}
try {
  $tpm = Get-Tpm -ErrorAction Stop
  $results.Add((Get-Status 'TPM present' ($tpm.TpmPresent -eq $true) ("Present={0} Ready={1}" -f $tpm.TpmPresent, $tpm.TpmReady)))
} catch {
  $results.Add((Get-Status 'TPM present' $false $_.Exception.Message))
}

# ---------- 2) Session lock / UAC / Fast Startup ----------
$idleSec = [math]::Max(60, $LockScreenMinutes * 60)
$results.Add((Set-Reg 'HKCU:\Control Panel\Desktop' 'ScreenSaveActive' '1' 'String'))
$results.Add((Set-Reg 'HKCU:\Control Panel\Desktop' 'ScreenSaverIsSecure' '1' 'String'))
$results.Add((Set-Reg 'HKCU:\Control Panel\Desktop' 'ScreenSaveTimeOut' "$idleSec" 'String'))
$results.Add((Set-Reg 'HKCU:\Control Panel\Desktop' 'ScreenSaveTimeOut' "$idleSec" 'String'))
# Require password on wake (AC/DC)
powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 1 | Out-Null
powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 1 | Out-Null
if ($Apply) { powercfg /SetActive SCHEME_CURRENT | Out-Null }
$results.Add((Get-Status 'Console lock on wake' $true 'powercfg CONSOLELOCK=1'))

# UAC: prompt consent for admins (1=prompt secure desktop is via ConsentPromptBehaviorAdmin=2)
$results.Add((Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA' 1))
$results.Add((Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'ConsentPromptBehaviorAdmin' 2))
$results.Add((Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'ConsentPromptBehaviorUser' 0))
$results.Add((Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'PromptOnSecureDesktop' 1))

# Fast Startup off
$results.Add((Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0))

# Guest account
try {
  if ($Apply) {
    Disable-LocalUser -Name 'Guest' -ErrorAction SilentlyContinue
    net user Guest /active:no 2>$null | Out-Null
  }
  $guest = Get-LocalUser -Name 'Guest' -ErrorAction SilentlyContinue
  $results.Add((Get-Status 'Guest disabled' (-not $guest -or -not $guest.Enabled) ("Enabled=$($guest.Enabled)")))
} catch {
  $results.Add((Get-Status 'Guest disabled' $false $_.Exception.Message))
}

# ---------- 3) BitLocker ----------
try {
  $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
  $on = $bl.ProtectionStatus -eq 'On'
  $results.Add((Get-Status "BitLocker $($env:SystemDrive)" $on ("Protection={0} VolumeStatus={1}" -f $bl.ProtectionStatus, $bl.VolumeStatus)))
  if ($Apply -and $EnableBitLocker -and -not $on) {
    if ($PSCmdlet.ShouldProcess($env:SystemDrive, 'Enable-BitLocker TPM+RecoveryPassword')) {
      Add-BitLockerKeyProtector -MountPoint $env:SystemDrive -TpmProtector -ErrorAction SilentlyContinue | Out-Null
      Enable-BitLocker -MountPoint $env:SystemDrive -EncryptionMethod XtsAes256 -UsedSpaceOnly -TpmProtector -ErrorAction Stop
      $rp = Add-BitLockerKeyProtector -MountPoint $env:SystemDrive -RecoveryPasswordProtector -ErrorAction SilentlyContinue
      $keyPath = Join-Path (Split-Path $LogPath) 'BitLocker-RecoveryKey.txt'
      "Drive=$($env:SystemDrive)`r`n$(Get-Date)`r`n$($rp | Format-List | Out-String)" | Set-Content -Path $keyPath -Encoding UTF8
      Write-Log "BitLocker enabled. Recovery info written to $keyPath - STORE OFFLINE." 'WARN'
      $results.Add((Get-Status 'BitLocker enable' $true "recovery file: $keyPath"))
    }
  } elseif (-not $on) {
    $results.Add((Get-Status 'BitLocker enable' $false 'use -Apply -EnableBitLocker (opt-in)'))
  }
} catch {
  $results.Add((Get-Status 'BitLocker' $false $_.Exception.Message))
}

# ---------- 4) Defender ----------
try {
  if ($Apply) {
    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
    Set-MpPreference -MAPSReporting Advanced -ErrorAction SilentlyContinue
    Set-MpPreference -SubmitSamplesConsent SendSafeSamples -ErrorAction SilentlyContinue
    Set-MpPreference -PUAProtection Enabled -ErrorAction SilentlyContinue
    Set-MpPreference -CloudBlockLevel High -ErrorAction SilentlyContinue
    Update-MpSignature -ErrorAction SilentlyContinue
  }
  $mp = Get-MpComputerStatus
  $ok = $mp.RealTimeProtectionEnabled -and $mp.AntivirusEnabled
  $results.Add((Get-Status 'Defender realtime' $ok ("AV={0} RT={1} Age={2}" -f $mp.AntivirusEnabled, $mp.RealTimeProtectionEnabled, $mp.AntivirusSignatureAge)))
} catch {
  $results.Add((Get-Status 'Defender realtime' $false $_.Exception.Message))
}

# SmartScreen
$results.Add((Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' 'SmartScreenEnabled' 'RequireAdmin' 'String'))
$results.Add((Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableSmartScreen' 1))

# ---------- 5) Firewall ----------
try {
  if ($Apply) {
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
    Set-NetFirewallProfile -Profile Public -DefaultInboundAction Block -DefaultOutboundAction Allow
  }
  $profiles = Get-NetFirewallProfile
  $allOn = @($profiles | Where-Object { $_.Enabled -eq $false }).Count -eq 0
  $results.Add((Get-Status 'Firewall all profiles on' $allOn (($profiles | ForEach-Object { "{0}={1}" -f $_.Name, $_.Enabled }) -join '; ')))
} catch {
  $results.Add((Get-Status 'Firewall' $false $_.Exception.Message))
}

# ---------- 6) Network hardening ----------
# SMBv1 off
try {
  if ($Apply) {
    Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue | Out-Null
    Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue
  }
  $smb1 = $false
  try { $smb1 = (Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue).State -eq 'Enabled' } catch {}
  $results.Add((Get-Status 'SMBv1 disabled' (-not $smb1) "SMB1 enabled=$smb1"))
} catch {
  $results.Add((Get-Status 'SMBv1 disabled' $false $_.Exception.Message))
}

# LLMNR off
$results.Add((Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'EnableMulticast' 0))
# NetBIOS over TCP/IP: via adapter WMI is messy; set NetbiosOptions=2 (disable) on IP-enabled adapters
try {
  $adapters = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=TRUE"
  foreach ($a in $adapters) {
    if ($Apply) { $a | Invoke-CimMethod -MethodName SetTcpipNetbios -Arguments @{TcpipNetbiosOptions = 2} | Out-Null }
  }
  $results.Add((Get-Status 'NetBIOS over TCP/IP disabled' $true "adapters=$($adapters.Count)"))
} catch {
  $results.Add((Get-Status 'NetBIOS over TCP/IP' $false $_.Exception.Message))
}

# AutoPlay off
$results.Add((Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoDriveTypeAutoRun' 255))
$results.Add((Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoDriveTypeAutoRun' 255))
$results.Add((Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers' 'DisableAutoplay' 1))

# Network discovery / firewall rules for public: keep default; ensure Public profile not discoverable
try {
  if ($Apply) {
    # Prefer Private for Ethernet if domain-less home/admin box - do not force; only document
  }
  $conn = Get-NetConnectionProfile -ErrorAction SilentlyContinue
  $results.Add((Get-Status 'Network profiles reviewed' ($null -ne $conn) (($conn | ForEach-Object { "{0}={1}" -f $_.Name, $_.NetworkCategory }) -join '; ')))
} catch {
  $results.Add((Get-Status 'Network profiles' $false $_.Exception.Message))
}

# ---------- 7) RDP ----------
try {
  $rdp = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -ErrorAction Stop).fDenyTSConnections
  $nla = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -ErrorAction SilentlyContinue).UserAuthentication
  if ($Apply -and $DisableRDP) {
    $results.Add((Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 1))
    Disable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
  } else {
    # If RDP left enabled, enforce NLA
    if ($rdp -eq 0) {
      $results.Add((Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' 'UserAuthentication' 1))
    }
    $results.Add((Get-Status 'RDP disabled' ($rdp -eq 1) ("fDenyTSConnections=$rdp NLA=$nla (use -DisableRDP to force off)")))
  }
} catch {
  $results.Add((Get-Status 'RDP posture' $false $_.Exception.Message))
}

# WinRM: leave alone unless open - report
try {
  $winrm = Get-Service WinRM -ErrorAction SilentlyContinue
  $results.Add((Get-Status 'WinRM service' ($winrm.Status -ne 'Running') ("Status=$($winrm.Status) StartType=$($winrm.StartType)")))
} catch {
  $results.Add((Get-Status 'WinRM service' $false $_.Exception.Message))
}

# ---------- 8) Audit policy (basic) ----------
if ($Apply) {
  auditpol /set /subcategory:"Logon" /success:enable /failure:enable | Out-Null
  auditpol /set /subcategory:"Logoff" /success:enable /failure:enable | Out-Null
  auditpol /set /subcategory:"Account Lockout" /success:enable /failure:enable | Out-Null
  auditpol /set /subcategory:"User Account Management" /success:enable /failure:enable | Out-Null
  auditpol /set /subcategory:"Security Group Management" /success:enable /failure:enable | Out-Null
  auditpol /set /subcategory:"Process Creation" /success:enable /failure:disable | Out-Null
}
$results.Add((Get-Status 'Audit policy basics' $true $(if ($Apply) { 'logon/account/process creation enabled' } else { 'run -Apply to enable' })))

# Include command line in process creation events
$results.Add((Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit' 'ProcessCreationIncludeCmdLine_Enabled' 1))

# ---------- 9) Power / sleep (laptop-friendly but lock) ----------
if ($Apply) {
  powercfg /change standby-timeout-ac 30 | Out-Null
  powercfg /change standby-timeout-dc 15 | Out-Null
  powercfg /change monitor-timeout-ac $LockScreenMinutes | Out-Null
  powercfg /change monitor-timeout-dc ([math]::Max(5, [int]($LockScreenMinutes / 2))) | Out-Null
}
$results.Add((Get-Status 'Sleep/monitor timeouts' $true "lock~$LockScreenMinutes min; AC standby 30; DC standby 15"))

# ---------- 10) Optional standard user ----------
if ($CreateStandardUser) {
  try {
    $u = Get-LocalUser -Name $CreateStandardUser -ErrorAction SilentlyContinue
    if (-not $u -and $Apply) {
      $pass = Read-Host "Password for new standard user '$CreateStandardUser'" -AsSecureString
      New-LocalUser -Name $CreateStandardUser -Password $pass -PasswordNeverExpires:$false -UserMayChangePassword:$true | Out-Null
      Add-LocalGroupMember -Group 'Users' -Member $CreateStandardUser -ErrorAction SilentlyContinue
      $results.Add((Get-Status "Create user $CreateStandardUser" $true 'created in Users group - use this for daily work'))
    } elseif ($u) {
      $results.Add((Get-Status "Create user $CreateStandardUser" $true 'already exists'))
    } else {
      $results.Add((Get-Status "Create user $CreateStandardUser" $false 'use -Apply -CreateStandardUser Name'))
    }
  } catch {
    $results.Add((Get-Status "Create user $CreateStandardUser" $false $_.Exception.Message))
  }
}

# ---------- 11) Listening high-risk ports report ----------
try {
  $listen = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalPort -in 22,23,135,139,445,3389,5985,5986,5900 } |
    Select-Object LocalAddress, LocalPort, OwningProcess
  $results.Add((Get-Status 'High-risk listen ports' (@($listen).Count -eq 0) (($listen | ForEach-Object { "{0}:{1} pid={2}" -f $_.LocalAddress, $_.LocalPort, $_.OwningProcess }) -join '; ')))
} catch {
  $results.Add((Get-Status 'High-risk listen ports' $false $_.Exception.Message))
}

# ---------- 12) Manual / not automated ----------
$manual = @(
  'Store BitLocker recovery key offline (password manager + printed copy)',
  'Use a standard (non-admin) account for daily work; elevate only when needed',
  'Enable MFA on Microsoft / Google / org admin accounts; prefer hardware key',
  'Install only approved admin tools (Sysinternals, Wireshark, RSAT as needed)',
  'Separate browser profile for admin vs personal; password manager required',
  'VPN required for remote admin to production',
  'Document asset owner, serial, software inventory, recovery path',
  'Firmware/BIOS password + Secure Boot already on - verify in firmware UI',
  'Consider HVCI / Credential Guard / ASR rules via org policy after compatibility check'
)
foreach ($m in $manual) {
  $results.Add([pscustomobject]@{ Item = 'MANUAL'; Status = 'TODO'; Detail = $m })
}

# ---------- Output ----------
$ok = @($results | Where-Object Status -eq 'OK').Count
$need = @($results | Where-Object Status -eq 'NEED').Count
$fixed = @($results | Where-Object Status -eq 'FIXED').Count
$todo = @($results | Where-Object Status -eq 'TODO').Count

Write-Log "Summary OK=$ok FIXED=$fixed NEED=$need MANUAL_TODO=$todo"
$results | Format-Table -AutoSize | Out-String | Write-Log

$csv = [IO.Path]::ChangeExtension($LogPath, '.csv')
$results | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
Write-Log "CSV report: $csv"

Write-Host ""
Write-Host "Harden-ITAdminPC complete  OK=$ok  FIXED=$fixed  NEED=$need  MANUAL=$todo"
Write-Host "Log: $LogPath"
Write-Host "CSV: $csv"
if (-not $Apply) {
  Write-Host "Re-run elevated with -Apply to implement. Opt-in: -EnableBitLocker -DisableRDP -CreateStandardUser Name"
}
