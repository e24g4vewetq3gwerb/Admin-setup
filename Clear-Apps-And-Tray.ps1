<#
.SYNOPSIS
  Clear removable apps. Taskbar shows only Start and PowerShell.

.DESCRIPTION
  Uninstalls removable Win32 and Store apps, hides tray and extra
  taskbar chrome, pins Windows PowerShell. Does not start explorer.exe.
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

function Test-NameLike([string]$Name, [string[]]$Patterns) {
  if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
  foreach ($pattern in $Patterns) {
    if ($Name -like $pattern) { return $true }
  }
  return $false
}

$homeRoot = Join-Path $env:USERPROFILE 'admin'
New-Item -ItemType Directory -Force -Path $homeRoot | Out-Null
$log = Join-Path $homeRoot 'Clear-Apps-And-Tray.log'

function Write-Log([string]$Message) {
  $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message
  try { $line | Tee-Object -FilePath $log -Append } catch { Write-Host $line }
}

Write-Host 'Clear-Apps-And-Tray 20260919d — Start + PowerShell only'
Write-Log 'Clear-Apps-And-Tray 20260919d — Start + PowerShell only'

if (-not (Test-IsAdmin)) {
  $self = Get-SelfPath
  if (-not $self) { $self = $MyInvocation.MyCommand.Definition }
  $arg = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', "`"$self`""
  )
  if ($SkipWipe) { $arg += '-SkipWipe' }
  if ($SkipTray) { $arg += '-SkipTray' }
  Write-Log 'Not elevated. Relaunching with RunAs.'
  Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList $arg | Out-Null
  return
}

Write-Log "==== start user=$env:USERNAME computer=$env:COMPUTERNAME ===="

function Invoke-UninstallCommand([string]$Command) {
  if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
  if ($Command -match '(?i)explorer(\.exe)?') {
    Write-Log "Skip uninstall that would call Explorer: $Command"
    return $false
  }
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
    if ($exe -match '(?i)explorer(\.exe)?$') {
      Write-Log "Skip explorer.exe uninstall: $Command"
      return $false
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
    'HP *',
    'Printer*',
    'Driver*',
    'Windows Terminal*',
    'Windows SDK*',
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
    'Microsoft.WindowsTerminal',
    'MicrosoftWindows.Client*',
    'Microsoft.Windows.*',
    'Microsoft.UI.*',
    'Microsoft.VCLibs*',
    'Microsoft.Services.Store*',
    'windows.immersivecontrolpanel',
    'Microsoft.DesktopAppInstaller',
    'Microsoft.SecHealthUI',
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

function Set-PowerShellTaskbarPin {
  $pinDir = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
  New-Item -ItemType Directory -Force -Path $pinDir | Out-Null
  Get-ChildItem -LiteralPath $pinDir -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -notmatch '(?i)powershell') {
      try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue } catch {}
    }
  }
  $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $lnk = Join-Path $pinDir 'Windows PowerShell.lnk'
  try {
    $w = New-Object -ComObject WScript.Shell
    $s = $w.CreateShortcut($lnk)
    $s.TargetPath = $ps
    $s.WorkingDirectory = (Join-Path $env:SystemRoot 'System32')
    $s.WindowStyle = 1
    $s.Description = 'Windows PowerShell'
    $s.IconLocation = "$ps,0"
    $s.Save()
    Write-Log "Pinned PowerShell shortcut: $lnk"
  } catch {
    Write-Log "PowerShell pin failed: $($_.Exception.Message)"
  }
}

function Set-MinimalTaskbar {
  Write-Host 'Taskbar: Start + PowerShell only (no Explorer restart)...'
  Write-Log 'Set-MinimalTaskbar'

  $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
  New-Item -Path $path -Force | Out-Null
  $vals = @{
    NoTrayItemsDisplay = 1
    HideClock          = 1
    HideSCAHealth      = 1
    HideSCAMeetNow     = 1
    HideSCANetwork     = 1
    HideSCAVolume      = 1
    HideSCAPower       = 1
    NoAutoTrayNotify   = 1
    HideLocaleBar      = 1
  }
  foreach ($k in $vals.Keys) {
    try { New-ItemProperty -Path $path -Name $k -Value $vals[$k] -PropertyType DWord -Force | Out-Null } catch {}
  }

  $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
  New-Item -Path $adv -Force | Out-Null
  $advVals = @{
    TaskbarAl            = 0
    ShowTaskViewButton   = 0
    TaskbarDa            = 0
    TaskbarMn            = 0
    ShowCopilotButton    = 0
    ShowTaskbarChat      = 0
    SearchboxTaskbarMode = 0
    ShowCortanaButton    = 0
    ShowStatusBar        = 0
    EnableAutoTray       = 1
    TaskbarSizeMove      = 0
  }
  foreach ($k in $advVals.Keys) {
    try { New-ItemProperty -Path $adv -Name $k -Value $advVals[$k] -PropertyType DWord -Force | Out-Null } catch {}
  }

  $search = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
  New-Item -Path $search -Force | Out-Null
  try { New-ItemProperty -Path $search -Name 'SearchboxTaskbarMode' -Value 0 -PropertyType DWord -Force | Out-Null } catch {}

  $fe = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
  New-Item -Path $fe -Force | Out-Null
  try { New-ItemProperty -Path $fe -Name 'HideRecommendedPersonalizedSites' -Value 1 -PropertyType DWord -Force | Out-Null } catch {}
  try { New-ItemProperty -Path $fe -Name 'DisableSearchBoxSuggestions' -Value 1 -PropertyType DWord -Force | Out-Null } catch {}

  $notify = 'HKCU:\Control Panel\NotifyIconSettings'
  if (Test-Path $notify) {
    Get-ChildItem $notify -ErrorAction SilentlyContinue | ForEach-Object {
      try { New-ItemProperty -Path $_.PSPath -Name 'IsPromoted' -Value 0 -PropertyType DWord -Force | Out-Null } catch {}
    }
  }

  $tip = 'HKCU:\Software\Microsoft\TabletTip\1.7'
  New-Item -Path $tip -Force | Out-Null
  try { New-ItemProperty -Path $tip -Name 'TipbandDesiredVisibility' -Value 0 -PropertyType DWord -Force | Out-Null } catch {}

  $lang = 'HKCU:\Software\Microsoft\CTF\LangBar'
  New-Item -Path $lang -Force | Out-Null
  try { New-ItemProperty -Path $lang -Name 'ShowStatus' -Value 3 -PropertyType DWord -Force | Out-Null } catch {}
  try { New-ItemProperty -Path $lang -Name 'ExtraIconsOnMinimized' -Value 0 -PropertyType DWord -Force | Out-Null } catch {}

  Set-PowerShellTaskbarPin
}

$win32 = 0
$store = 0
if ($SkipWipe) {
  Write-Log 'SkipWipe set. Leaving apps installed.'
} else {
  Write-Host 'Clearing installed apps (no prompts)...'
  $win32 = Invoke-ClearWin32Apps
  $store = Invoke-ClearStoreApps
}

if ($SkipTray) {
  Write-Log 'SkipTray set. Leaving taskbar as-is.'
} else {
  Set-MinimalTaskbar
}

Write-Log "Finished. Win32 attempts=$win32 Store attempts=$store"
Write-Host "Done. Win32 uninstalls: $win32  Store removals: $store"
Write-Host 'Taskbar target: Start + Windows PowerShell only. Sign out/in if the pin is not visible yet.'
Write-Host "Log: $log"
