# Complete remaining NEED items
$ErrorActionPreference = 'Continue'
$logDir = "$env:USERPROFILE\admin\scripts"
$log = Join-Path $logDir 'complete-need.log'
function L([string]$m) {
  $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $m
  $line | Tee-Object -FilePath $log -Append
}
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
L ("==== complete-need elevated=$isAdmin ====")

$adapters = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=TRUE')
L ("adapters=$($adapters.Count)")
foreach ($a in $adapters) {
  $r = $a | Invoke-CimMethod -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = 2 }
  L ("NetBIOS $($a.Description) result=$($r.ReturnValue)")
}

$rules = @(
  @{ Name='Harden Block inbound TCP 445'; Protocol='TCP'; Port='445' },
  @{ Name='Harden Block inbound TCP 139'; Protocol='TCP'; Port='139' },
  @{ Name='Harden Block inbound TCP 135'; Protocol='TCP'; Port='135' },
  @{ Name='Harden Block inbound UDP 137'; Protocol='UDP'; Port='137' },
  @{ Name='Harden Block inbound UDP 138'; Protocol='UDP'; Port='138' }
)
foreach ($r in $rules) {
  Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
  New-NetFirewallRule -DisplayName $r.Name -Direction Inbound -Action Block -Protocol $r.Protocol -LocalPort $r.Port -Profile Any -Enabled True | Out-Null
  L ("FW block $($r.Protocol)/$($r.Port)")
}
Get-NetFirewallRule -DisplayGroup 'File and Printer Sharing' -ErrorAction SilentlyContinue | Disable-NetFirewallRule -ErrorAction SilentlyContinue
Get-NetFirewallRule -DisplayGroup 'Network Discovery' -ErrorAction SilentlyContinue | Disable-NetFirewallRule -ErrorAction SilentlyContinue
L 'Disabled File and Printer Sharing + Network Discovery FW groups'

try {
  Set-SmbServerConfiguration -EnableSMB2Protocol $false -Force -ErrorAction Stop
  L 'SMB2 server protocol disabled'
} catch { L ("SMB2 warn: $($_.Exception.Message)") }
try {
  Stop-Service LanmanServer -Force -ErrorAction SilentlyContinue
  Set-Service LanmanServer -StartupType Disabled -ErrorAction SilentlyContinue
  L 'LanmanServer stopped+Disabled'
} catch { L ("LanmanServer warn: $($_.Exception.Message)") }

try {
  $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
  L ("BitLocker before Protection=$($bl.ProtectionStatus) Status=$($bl.VolumeStatus)")
  if ($bl.ProtectionStatus -ne 'On') {
    $tpmReady = $false
    try { $tpmReady = [bool](Get-Tpm).TpmReady } catch {}
    if ($tpmReady) {
      Enable-BitLocker -MountPoint $env:SystemDrive -EncryptionMethod XtsAes256 -UsedSpaceOnly -TpmProtector -ErrorAction Stop
      L 'Enable-BitLocker TPM started'
    } else {
      Enable-BitLocker -MountPoint $env:SystemDrive -EncryptionMethod XtsAes256 -UsedSpaceOnly -RecoveryPasswordProtector -ErrorAction Stop
      L 'Enable-BitLocker RecoveryPassword started'
    }
    $bl2 = Get-BitLockerVolume -MountPoint $env:SystemDrive
    $rp = $bl2.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
    if (-not $rp) {
      Add-BitLockerKeyProtector -MountPoint $env:SystemDrive -RecoveryPasswordProtector | Out-Null
      $bl2 = Get-BitLockerVolume -MountPoint $env:SystemDrive
      $rp = $bl2.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
    }
    $keyPath = Join-Path $logDir 'BitLocker-RecoveryKey.txt'
    $txt = "BitLocker recovery key for $($env:COMPUTERNAME) drive $($env:SystemDrive)`r`nGenerated: $(Get-Date -Format o)`r`nId: $($rp.KeyProtectorId)`r`nPassword: $($rp.RecoveryPassword)`r`n`r`nSTORE THIS OFFLINE. Do not leave only on this encrypted drive.`r`n"
    Set-Content -Path $keyPath -Value $txt -Encoding UTF8
    Copy-Item $keyPath "$env:USERPROFILE\Desktop\BitLocker-RecoveryKey.txt" -Force
    L ("Recovery key written: $keyPath and Desktop")
  } else {
    L 'BitLocker already On'
  }
} catch {
  L ("BitLocker ERROR: $($_.Exception.Message)")
}

try {
  $sb = Confirm-SecureBootUEFI
  L ("SecureBoot=$sb")
  if (-not $sb) {
    $helpPath = Join-Path $logDir 'SecureBoot-HOW-TO.txt'
    $help = @(
      'Secure Boot is OFF. Enable it in UEFI firmware:',
      '',
      '1. Settings - System - Recovery - Advanced startup - Restart now',
      '2. Troubleshoot - Advanced options - UEFI Firmware Settings - Restart',
      '3. Firmware: Security - Secure Boot - Enabled - Save and Exit',
      '',
      'Or elevated: shutdown /r /fw /t 60',
      'Cancel: shutdown /a'
    ) -join "`r`n"
    Set-Content -Path $helpPath -Value $help -Encoding UTF8
    L ("Wrote $helpPath")
  }
} catch {
  L ("SecureBoot check: $($_.Exception.Message)")
}

$listen = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
  Where-Object { $_.LocalPort -in 135,139,445,3389 } |
  ForEach-Object { "$($_.LocalAddress):$($_.LocalPort)" }
L ("Listen after: $($listen -join '; ')")
try {
  $bl3 = Get-BitLockerVolume -MountPoint $env:SystemDrive
  L ("BitLocker after Protection=$($bl3.ProtectionStatus) Status=$($bl3.VolumeStatus) Pct=$($bl3.EncryptionPercentage)")
} catch {}
L '==== done ===='
