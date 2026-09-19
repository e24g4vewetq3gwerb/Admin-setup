<#
.SYNOPSIS
  Clear removable apps. Hide the taskbar; Start + PowerShell only when it slides out.
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

Write-Host 'Clear-Apps-And-Tray 20260919f — auto-hide taskbar'
Write-Log 'Clear-Apps-And-Tray 20260919f — auto-hide taskbar'

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
    if ($exe -match '(?i)explorer(\.exe)?$') { Write-Log "Skip explorer.exe uninstall: $Command"; return $false }
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
    'Realtek*','Microsoft Visual C++*','Microsoft Visual Studio* Redistributable*',
    'Microsoft .NET*','Microsoft Edge*','Microsoft Edge WebView2*','Microsoft Update*',
    'Windows PC Health Check*','Update for *','Security Update*','Hotfix*',
    'Intel*','NVIDIA*','AMD*','Chipset*','Canon *','HP *','Printer*','Driver*',
    'Windows Terminal*','Windows SDK*','Microsoft Windows*','Windows Malicious Software Removal*'
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
    if (Test-NameLike $name $protect) { Write-Log "Keep Win32: $name"; continue }
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
    'Microsoft.WindowsStore','Microsoft.StorePurchaseApp','Microsoft.WindowsTerminal',
    'MicrosoftWindows.Client*','Microsoft.Windows.*','Microsoft.UI.*','Microsoft.VCLibs*',
    'Microsoft.Services.Store*','windows.immersivecontrolpanel','Microsoft.DesktopAppInstaller',
    'Microsoft.SecHealthUI','Microsoft.MicrosoftEdge*','Microsoft.ECApp','Microsoft.LockApp',
    'Microsoft.AAD.BrokerPlugin','Microsoft.AccountsControl','Microsoft.BioEnrollment',
    'Microsoft.CredDialogHost','Microsoft.Win32WebViewHost','Microsoft.XboxGameCallableUI',
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
        try { Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue; $removed++ } catch {
          Write-Log "Store remove failed: $name $($_.Exception.Message)"
        }
      }
    }
  } catch { Write-Log "AppX enumeration failed: $($_.Exception.Message)" }
  return $removed
}

function Get-PowerShellStartLnk {
  $candidates = @(
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Windows PowerShell\Windows PowerShell.lnk'),
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Windows PowerShell\Windows PowerShell.lnk'),
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\System Tools\Windows PowerShell.lnk'),
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\System Tools\Windows PowerShell.lnk')
  )
  foreach ($p in $candidates) { if (Test-Path -LiteralPath $p) { return $p } }
  $dir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Windows PowerShell'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $lnk = Join-Path $dir 'Windows PowerShell.lnk'
  $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $w = New-Object -ComObject WScript.Shell
  $s = $w.CreateShortcut($lnk)
  $s.TargetPath = $ps
  $s.WorkingDirectory = (Join-Path $env:SystemRoot 'System32')
  $s.IconLocation = "$ps,0"
  $s.Save()
  return $lnk
}

function Set-TaskbarLayoutXml {
  $lnk = Get-PowerShellStartLnk
  $lnkAttr = $lnk -replace '&','&amp;' -replace '"','&quot;'
  $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification" xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout" Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
        <taskbar:DesktopApp DesktopApplicationLinkPath="$lnkAttr"/>
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@
  $shellDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Shell'
  New-Item -ItemType Directory -Force -Path $shellDir | Out-Null
  $xmlPath = Join-Path $shellDir 'LayoutModification.xml'
  [System.IO.File]::WriteAllText($xmlPath, $xml, [Text.UTF8Encoding]::new($false))
  Write-Log "Wrote $xmlPath"
  foreach ($pol in @('HKCU:\Software\Policies\Microsoft\Windows\Explorer','HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer')) {
    New-Item -Path $pol -Force | Out-Null
    New-ItemProperty -Path $pol -Name 'StartLayoutFile' -Value $xmlPath -PropertyType String -Force | Out-Null
  }
}

function Enable-TaskbarAutoHide {
  Write-Log 'Enable taskbar auto-hide (StuckRects)'
  foreach ($key in @('StuckRects3','StuckRects2')) {
    $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\$key"
    if (-not (Test-Path $p)) { continue }
    try {
      $s = [byte[]](Get-ItemProperty -Path $p).Settings
      if ($s -and $s.Length -gt 8) {
        $s[8] = [byte]($s[8] -bor 0x01)
        Set-ItemProperty -Path $p -Name Settings -Value $s
        Write-Log "Auto-hide bit set on $key"
      }
    } catch { Write-Log "StuckRects $key failed: $($_.Exception.Message)" }
  }
}

function Restart-ShellNoFolderWindow {
  Write-Log 'Refreshing shell: stop explorer only'
  try { Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}
  $deadline = (Get-Date).AddSeconds(10)
  while (-not (Get-Process explorer -ErrorAction SilentlyContinue)) {
    if ((Get-Date) -gt $deadline) {
      Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList '/NOUACCHECK' | Out-Null
      break
    }
    Start-Sleep -Milliseconds 300
  }
}

function Set-MinimalTaskbar {
  Write-Host 'Hiding taskbar (auto-hide). Start + PowerShell when the bar slides out.'
  Write-Log 'Set-MinimalTaskbar'

  $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
  New-Item -Path $path -Force | Out-Null
  $vals = @{
    NoTrayItemsDisplay = 1; HideClock = 1; HideSCAHealth = 1; HideSCAMeetNow = 1
    HideSCANetwork = 1; HideSCAVolume = 1; HideSCAPower = 1; NoAutoTrayNotify = 1; HideLocaleBar = 1
  }
  foreach ($k in $vals.Keys) {
    try { New-ItemProperty -Path $path -Name $k -Value $vals[$k] -PropertyType DWord -Force | Out-Null } catch {}
  }

  $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
  New-Item -Path $adv -Force | Out-Null
  $advVals = @{
    TaskbarAl = 0; ShowTaskViewButton = 0; TaskbarDa = 0; TaskbarMn = 0
    ShowCopilotButton = 0; ShowTaskbarChat = 0; SearchboxTaskbarMode = 0; ShowCortanaButton = 0; EnableAutoTray = 1
  }
  foreach ($k in $advVals.Keys) {
    try { New-ItemProperty -Path $adv -Name $k -Value $advVals[$k] -PropertyType DWord -Force | Out-Null } catch {}
  }

  $search = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
  New-Item -Path $search -Force | Out-Null
  try { New-ItemProperty -Path $search -Name 'SearchboxTaskbarMode' -Value 0 -PropertyType DWord -Force | Out-Null } catch {}

  Enable-TaskbarAutoHide
  Set-TaskbarLayoutXml
  Restart-ShellNoFolderWindow
}

$win32 = 0
$store = 0
if ($SkipWipe) { Write-Log 'SkipWipe set.' } else {
  Write-Host 'Clearing installed apps (no prompts)...'
  $win32 = Invoke-ClearWin32Apps
  $store = Invoke-ClearStoreApps
}
if ($SkipTray) { Write-Log 'SkipTray set.' } else { Set-MinimalTaskbar }

Write-Log "Finished. Win32 attempts=$win32 Store attempts=$store"
Write-Host "Done. Win32 uninstalls: $win32  Store removals: $store"
Write-Host 'Taskbar is auto-hidden. Move the mouse to the bottom edge for Start + PowerShell.'
Write-Host "Log: $log"
