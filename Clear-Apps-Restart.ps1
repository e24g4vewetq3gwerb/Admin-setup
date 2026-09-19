<#
.SYNOPSIS
  Silent workstation wipe: uninstall removable apps, then restart.
  No Yes/No boxes. No Read-Host. No confirmations.

.DESCRIPTION
  Intended for an already-trusted admin session on a lab / kiosk / reset box.
  Windows UAC still appears if this process is not elevated — that prompt is
  from the OS, not from this script. There is no supported way to skip UAC.

  Protects drivers, runtimes, Edge/WebView2, and non-removable system packages
  so the machine can still boot. Everything else with an uninstall string or a
  removable AppX package is removed quietly.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Clear-Apps-Restart.ps1
#>
[CmdletBinding()]
param(
  [switch]$NoRestart,
  [int]$RestartDelaySeconds = 15
)
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

function Test-IsAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Prop {
  param($Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $prop = $Object.PSObject.Properties[$Name]
  if ($prop) { return $prop.Value }
  return $null
}

function Get-SelfPath {
  foreach ($candidate in @(
    $PSCommandPath,
    (Get-Prop $MyInvocation.MyCommand 'Path'),
    (Get-Prop $MyInvocation.MyCommand 'Definition')
  )) {
    if ($candidate -and $candidate -like '*.ps1' -and (Test-Path -LiteralPath $candidate)) {
      return $candidate
    }
  }
  return $null
}

$homeRoot = Join-Path $env:USERPROFILE 'admin'
New-Item -ItemType Directory -Force -Path $homeRoot | Out-Null
$log = Join-Path $homeRoot 'Clear-Apps-Restart.log'

function Write-Log([string]$Message) {
  $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message
  try { $line | Tee-Object -FilePath $log -Append } catch { Write-Host $line }
}

if (-not (Test-IsAdmin)) {
  $self = Get-SelfPath
  if (-not $self) { $self = $MyInvocation.MyCommand.Definition }
  $arg = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', "`"$self`""
  )
  if ($NoRestart) { $arg += '-NoRestart' }
  $arg += @('-RestartDelaySeconds', "$RestartDelaySeconds")
  Write-Log "Not elevated. Relaunching with RunAs."
  Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList $arg | Out-Null
  return
}

Write-Log "==== Clear-Apps-Restart start user=$env:USERNAME computer=$env:COMPUTERNAME ===="

function Test-NameLike([string]$Name, [string[]]$Patterns) {
  if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
  foreach ($pattern in $Patterns) {
    if ($Name -like $pattern) { return $true }
  }
  return $false
}

function Invoke-UninstallCommand([string]$Command) {
  if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
  try {
    if ($Command -match '\{([0-9A-Fa-f-]{36})\}') {
      $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @("/X{$($Matches[1])}", '/qn', '/norestart') -Wait -PassThru -WindowStyle Hidden
      return ($p.ExitCode -in 0, 1605, 1614, 1641, 3010)
    }
    $exe = $Command
    $args = ''
    if ($Command -match '^"([^"]+)"\s*(.*)$') {
      $exe = $Matches[1]
      $args = [string]$Matches[2]
    } elseif ($Command -match '^(\S+)\s*(.*)$') {
      $exe = $Matches[1]
      $args = [string]$Matches[2]
    }
    if (-not (Test-Path -LiteralPath $exe)) { return $false }
    $low = "$args".ToLowerInvariant()
    if ($low -notmatch '/s\b|/silent|/quiet|/qn|/norestart') {
      $args = ("$args /S /silent /quiet /norestart").Trim()
    }
    $p = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
    return ($null -eq $p.ExitCode -or $p.ExitCode -in 0, 1, 1605, 1614, 1641, 3010)
  } catch {
    Write-Log "Uninstall command failed: $($_.Exception.Message)"
    return $false
  }
}

function Invoke-ClearWin32Apps {
  $protect = @(
    'Realtek*',
    'Microsoft Visual C++*',
    'Microsoft Visual Studio* Redistributable*',
    'Microsoft .NET*',
    'Microsoft Edge*',
    'Microsoft Edge WebView2*',
    'Microsoft Update*',
    'Windows PC Health Check*',
    'Update for *',
    'Security Update*',
    'Hotfix*',
    'Intel*',
    'NVIDIA*',
    'AMD*',
    'Chipset*',
    'Canon *',
    'Printer*',
    'Driver*',
    'Windows Terminal*',
    'Windows SDK*',
    'Microsoft OneDrive*',
    'Microsoft Windows*',
    'Windows Malicious Software Removal*'
  )
  $paths = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
  $removed = 0
  foreach ($prog in @(Get-ItemProperty $paths -ErrorAction SilentlyContinue)) {
    $name = [string](Get-Prop $prog 'DisplayName')
    if (-not $name) { continue }
    $systemComponent = Get-Prop $prog 'SystemComponent'
    if ($null -ne $systemComponent) {
      try { if ([int]$systemComponent -eq 1) { continue } } catch {}
    }
    if (Test-NameLike $name $protect) {
      Write-Log "Keep Win32: $name"
      continue
    }
    $uninstall = [string](Get-Prop $prog 'QuietUninstallString')
    if (-not $uninstall) { $uninstall = [string](Get-Prop $prog 'UninstallString') }
    if (-not $uninstall) { continue }
    Write-Host "Uninstall $name"
    Write-Log "Uninstall $name :: $uninstall"
    if (Invoke-UninstallCommand $uninstall) { $removed++ }
  }
  return $removed
}

function Invoke-ClearStoreApps {
  $keepAppx = @(
    'Microsoft.WindowsStore',
    'Microsoft.StorePurchaseApp',
    'Microsoft.WindowsCalculator',
    'Microsoft.Windows.Photos',
    'Microsoft.WindowsTerminal',
    'MicrosoftWindows.Client*',
    'Microsoft.Windows.*',
    'Microsoft.UI.*',
    'Microsoft.VCLibs*',
    'Microsoft.Services.Store*',
    'windows.immersivecontrolpanel',
    'Microsoft.DesktopAppInstaller',
    'Microsoft.SecHealthUI',
    'Microsoft.Paint',
    'Microsoft.ScreenSketch',
    'Microsoft.WindowsNotepad',
    'Microsoft.WindowsAlarms',
    'Microsoft.WindowsSoundRecorder',
    'Microsoft.WindowsCamera',
    'Microsoft.WindowsMaps',
    'Microsoft.MicrosoftEdge*',
    'Microsoft.ECApp',
    'Microsoft.LockApp',
    'Microsoft.AAD.BrokerPlugin',
    'Microsoft.AccountsControl',
    'Microsoft.BioEnrollment',
    'Microsoft.CredDialogHost',
    'Microsoft.Win32WebViewHost',
    'Microsoft.XboxGameCallableUI',
    'Microsoft.PPIProjection'
  )
  $removed = 0
  try {
    foreach ($pkg in @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)) {
      $name = [string]$pkg.Name
      if (-not $name) { continue }
      if ($pkg.IsFramework) { continue }
      if ($pkg.NonRemovable) { continue }
      if (Test-NameLike $name $keepAppx) { continue }
      if ($name -like 'Microsoft.Windows.*' -or $name -like 'Windows.*') { continue }
      Write-Host "Remove Store app $name"
      Write-Log "Remove Store app $($pkg.PackageFullName)"
      try {
        Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue
        $removed++
      } catch {
        try {
          Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue
          $removed++
        } catch {
          Write-Log "Store remove failed: $name $($_.Exception.Message)"
        }
      }
    }
  } catch {
    Write-Log "AppX enumeration failed: $($_.Exception.Message)"
  }
  return $removed
}

Write-Host 'Clearing installed apps (no prompts)...'
$win32 = Invoke-ClearWin32Apps
$store = Invoke-ClearStoreApps
Write-Log "Finished. Win32 attempts=$win32 Store attempts=$store"
Write-Host "Done. Win32 uninstalls: $win32  Store removals: $store"
Write-Host "Log: $log"

if ($NoRestart) {
  Write-Log 'NoRestart set. Skipping reboot.'
  return
}

$delay = [Math]::Max(0, [int]$RestartDelaySeconds)
Write-Host "Restarting in $delay seconds. Cancel with: shutdown /a"
Write-Log "Restart scheduled in $delay seconds"
shutdown.exe /r /t $delay /f /c 'Clear-Apps-Restart finished.'
