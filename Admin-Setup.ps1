<#
.SYNOPSIS
  Admin Setup. One desktop icon on the home screen, then optional installs.
#>
[CmdletBinding()]
param(
  [switch]$Apply,
  [switch]$UninstallNotKept,
  [switch]$Restart,
  [switch]$RestartIfNeeded,
  [switch]$SkipWipe,
  [switch]$SkipOffer,
  [switch]$DesktopIcon,
  [switch]$SkipDesktopIcon,
  [switch]$IconOnly,
  [switch]$ForceAsk
)
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
function Test-IsAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-Prop {
  param($Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $p = $Object.PSObject.Properties[$Name]
  if ($p) { return $p.Value }
  return $null
}
$homeRoot = Join-Path $env:USERPROFILE 'admin'
New-Item -ItemType Directory -Force -Path $homeRoot | Out-Null
$log = Join-Path $homeRoot 'Admin-Setup.log'
function Write-Log([string]$m) {
  $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $m
  $line | Tee-Object -FilePath $log -Append
}
function Get-SelfPath {
  if ($PSCommandPath) { return $PSCommandPath }
  if ($MyInvocation.MyCommand.Path) { return $MyInvocation.MyCommand.Path }
  return $null
}
$persist = Join-Path $homeRoot 'Admin-Setup.ps1'
$self = Get-SelfPath
if ($self -and (Test-Path -LiteralPath $self)) {
  try {
    if ((Resolve-Path $self).Path -ne (Resolve-Path $persist -ErrorAction SilentlyContinue).Path) {
      Copy-Item -LiteralPath $self -Destination $persist -Force
    }
  } catch { Copy-Item -LiteralPath $self -Destination $persist -Force -ErrorAction SilentlyContinue }
}
if (-not (Test-Path -LiteralPath $persist) -and $self -and (Test-Path $self)) {
  Copy-Item -LiteralPath $self -Destination $persist -Force
}
function Get-ExplorerDesktop {
  try { return (New-Object -ComObject Shell.Application).NameSpace(0x10).Self.Path } catch {}
  return [Environment]::GetFolderPath('Desktop')
}
function Show-DesktopHomeIcons {
  $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
  New-Item -Path $adv -Force | Out-Null
  Set-ItemProperty -Path $adv -Name HideIcons -Value 0 -Type DWord
  foreach ($sub in @('NewStartPanel','ClassicStartMenu')) {
    $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\$sub"
    New-Item -Path $p -Force | Out-Null
    Set-ItemProperty -Path $p -Name '{645FF040-5081-101B-9F08-00AA002F954E}' -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $p -Name '{20D04FE0-3AEA-1069-A2D8-08002B30309D}' -Value 0 -Type DWord -ErrorAction SilentlyContinue
  }
  try {
    Add-Type -Namespace Native -Name ShellNotify -MemberDefinition @'
      [System.Runtime.InteropServices.DllImport("shell32.dll")]
      public static extern void SHChangeNotify(uint wEventId, uint uFlags, System.IntPtr dwItem1, System.IntPtr dwItem2);
'@ -ErrorAction SilentlyContinue
    [Native.ShellNotify]::SHChangeNotify(0x8000000, 0x1000, [IntPtr]::Zero, [IntPtr]::Zero)
  } catch {}
  Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
}
function Remove-ExtraAdminIcons {
  $keepDesk = Get-ExplorerDesktop
  $keepLnk = Join-Path $keepDesk 'Admin Setup.lnk'
  $extra = @(
    (Join-Path $env:USERPROFILE 'Desktop\Admin Setup.lnk'),
    (Join-Path $env:USERPROFILE 'Desktop\Admin Setup.cmd'),
    (Join-Path $env:USERPROFILE 'OneDrive\Desktop\Admin Setup.lnk'),
    (Join-Path $env:USERPROFILE 'OneDrive\Desktop\Admin Setup.cmd'),
    (Join-Path $env:PUBLIC 'Desktop\Admin Setup.lnk'),
    (Join-Path $env:PUBLIC 'Desktop\Admin Setup.cmd'),
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Admin Setup.lnk'),
    (Join-Path $homeRoot 'Admin Setup.cmd')
  )
  foreach ($p in $extra) {
    if (-not $p) { continue }
    if ($keepLnk -and (([string]$p).ToLower() -eq ([string]$keepLnk).ToLower())) { continue }
    if (Test-Path -LiteralPath $p) { try { Remove-Item -LiteralPath $p -Force } catch {} }
  }
}
function Install-DesktopIcon {
  Remove-ExtraAdminIcons
  $desk = Get-ExplorerDesktop
  $lnkPath = Join-Path $desk 'Admin Setup.lnk'
  $w = New-Object -ComObject WScript.Shell
  $sc = $w.CreateShortcut($lnkPath)
  $sc.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
  $sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$persist`" -Apply -UninstallNotKept -RestartIfNeeded"
  $sc.WorkingDirectory = $homeRoot
  $sc.WindowStyle = 1
  $sc.Description = 'Admin Setup'
  $sc.IconLocation = "$env:SystemRoot\System32\imageres.dll,109"
  $sc.Save()
  Show-DesktopHomeIcons
  Write-Host "Desktop icon: $lnkPath"
  Write-Host 'Desktop icons were un-hidden and Explorer refreshed.'
  Write-Host 'To pin beside Start: right-click the desktop icon -> Show more options -> Pin to taskbar.'
  return $lnkPath
}
if (-not $SkipDesktopIcon) { Install-DesktopIcon | Out-Null }
if ($IconOnly) { exit 0 }
if (-not (Test-IsAdmin)) {
  $arg = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$persist`"", '-SkipDesktopIcon')
  if ($Apply) { $arg += '-Apply' }
  if ($UninstallNotKept) { $arg += '-UninstallNotKept' }
  if ($Restart) { $arg += '-Restart' }
  if ($RestartIfNeeded) { $arg += '-RestartIfNeeded' }
  if ($SkipWipe) { $arg += '-SkipWipe' }
  if ($SkipOffer) { $arg += '-SkipOffer' }
  if ($ForceAsk) { $arg += '-ForceAsk' }
  Start-Process powershell.exe -Verb RunAs -ArgumentList $arg | Out-Null
  return
}
Write-Log "==== Admin-Setup start elevated=$(Test-IsAdmin) ===="
Add-Type -AssemblyName System.Windows.Forms | Out-Null
function Test-NameLike([string]$Name, [string[]]$Patterns) {
  if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
  foreach ($p in $Patterns) { if ($Name -like $p) { return $true } }
  return $false
}
function Get-UninstallHits([string[]]$Patterns) {
  Get-ItemProperty @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*') -ErrorAction SilentlyContinue |
    Where-Object { $dn = [string](Get-Prop $_ 'DisplayName'); $dn -and (Test-NameLike $dn $Patterns) }
}
function Test-GrokBotInstalled {
  foreach ($e in @("$env:LOCALAPPDATA\Programs\Grok Bot\Grok Bot.exe","${env:ProgramFiles}\Grok Bot\Grok Bot.exe","${env:ProgramFiles(x86)}\Grok Bot\Grok Bot.exe")) { if ($e -and (Test-Path -LiteralPath $e)) { return $true } }
  return [bool](Get-UninstallHits @('Grok Bot*'))
}
function Test-ChromeInstalled {
  foreach ($e in @("${env:ProgramFiles}\Google\Chrome\Application\chrome.exe","${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe","$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")) { if ($e -and (Test-Path -LiteralPath $e)) { return $true } }
  return [bool](Get-UninstallHits @('Google Chrome*'))
}
function Save-Url {
  param([string]$Url, [string]$Dest)
  New-Item -ItemType Directory -Force -Path (Split-Path $Dest) | Out-Null
  if (Test-Path -LiteralPath $Dest) { Remove-Item -LiteralPath $Dest -Force -ErrorAction SilentlyContinue }
  $ok = $false
  try { Start-BitsTransfer -Source $Url -Destination $Dest -ErrorAction Stop; $ok = $true } catch {}
  if (-not $ok) { try { Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -TimeoutSec 600; $ok = $true } catch {} }
  if (-not $ok) { $curl = "$env:SystemRoot\System32\curl.exe"; if (Test-Path $curl) { & $curl -L --retry 3 -o $Dest $Url; if ($LASTEXITCODE -eq 0) { $ok = $true } } }
  if (-not (Test-Path -LiteralPath $Dest)) { throw "Download produced no file: $Url" }
  if ((Get-Item -LiteralPath $Dest).Length -lt 500KB) { throw "Download too small: $Url" }
  return $Dest
}
function Get-GrokBotSetupInfo {
  $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'win32-arm64' } else { 'win32-x64' }
  $info = [pscustomobject]@{ Url = $null; Version = 'unknown' }
  foreach ($page in @('https://cursor.com/download/bot','https://www.cursor.com/download/bot')) {
    try {
      $html = (Invoke-WebRequest -Uri $page -UseBasicParsing -TimeoutSec 60).Content
      $re = "https://downloads\.cursor\.com/grokbot/stable/$arch/[^`"'\s<>]+\.exe"
      if ($html -match $re) { $info.Url = $Matches[0]; if ($info.Url -match '/(\d+\.\d+\.\d+)/') { $info.Version = $Matches[1] }; break }
    } catch {}
  }
  if (-not $info.Url) { $info.Url = "https://downloads.cursor.com/grokbot/stable/$arch/0.47.0/Grok_Bot_0.47.0_Setup.exe"; $info.Version = '0.47.0-fallback' }
  return $info
}
function Get-ChromeSetupInfo { [pscustomobject]@{ Url = 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi'; Fallback = 'https://dl.google.com/chrome/install/latest/chrome_installer.exe'; Version = 'latest-stable' } }
function Install-GrokBot([string]$Url) {
  $dest = Join-Path $env:TEMP 'AdminSetup-Grok_Bot_Setup.exe'
  Write-Host 'Downloading Grok Bot...'; Save-Url -Url $Url -Dest $dest | Out-Null
  Write-Host 'Installing Grok Bot...'
  $p = Start-Process -FilePath $dest -ArgumentList '/S' -PassThru -Wait
  if ($null -eq $p.ExitCode -or $p.ExitCode -notin @(0, 1)) { $p = Start-Process -FilePath $dest -PassThru -Wait }
  return $p.ExitCode
}
function Install-Chrome($Info) {
  $dir = Join-Path $env:TEMP 'AdminSetup-Chrome'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $msi = Join-Path $dir 'ChromeEnterprise64.msi'
  Write-Host 'Downloading Google Chrome...'
  try {
    Save-Url -Url $Info.Url -Dest $msi | Out-Null
    $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', "`"$msi`"", '/qn', '/norestart') -PassThru -Wait
    if ($p.ExitCode -in 0, 3010) { return $p.ExitCode }
    throw "msiexec $($p.ExitCode)"
  } catch {
    $exe = Join-Path $dir 'chrome_installer.exe'
    Save-Url -Url $Info.Fallback -Dest $exe | Out-Null
    $p = Start-Process -FilePath $exe -ArgumentList '/silent /install' -PassThru -Wait
    return $p.ExitCode
  }
}
function Invoke-OfferInstall {
  $grokHave = Test-GrokBotInstalled; $chromeHave = Test-ChromeInstalled
  $grok = Get-GrokBotSetupInfo; $chrome = Get-ChromeSetupInfo
  $needGrok = (-not $grokHave) -or $ForceAsk; $needChrome = (-not $chromeHave) -or $ForceAsk
  $lines = @('Install the latest apps now? (before any restart)','', $(if ($needGrok) { "- Grok Bot  $($grok.Version)" } else { '- Grok Bot  (already installed)' }), $(if ($needChrome) { "- Google Chrome  $($chrome.Version)" } else { '- Google Chrome  (already installed)' }),'','Yes = download and install now while this window is elevated.','No  = skip apps.')
  $caption = 'Admin Setup - Grok Bot + Chrome'
  $result = [Windows.Forms.MessageBox]::Show(($lines -join "`r`n"), $caption, [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Question)
  if ($result -ne [Windows.Forms.DialogResult]::Yes) { return $false }
  $errors = New-Object System.Collections.Generic.List[string]
  try {
    if ($needGrok) { $code = Install-GrokBot -Url $grok.Url; if ($code -notin 0, 1, $null) { $errors.Add("Grok Bot exit $code") } }
    if ($needChrome) { $code = Install-Chrome -Info $chrome; if ($code -notin 0, 3010, $null) { $errors.Add("Chrome exit $code") } }
  } catch { $errors.Add($_.Exception.Message) }
  $g2 = Test-GrokBotInstalled; $c2 = Test-ChromeInstalled
  $summary = @($(if ($g2) { 'Grok Bot: installed' } else { 'Grok Bot: not found after install' }), $(if ($c2) { 'Chrome: installed' } else { 'Chrome: not found after install' }))
  if ($errors.Count -gt 0) { $summary += ''; $summary += $errors }
  [Windows.Forms.MessageBox]::Show(($summary -join "`r`n"), $caption, [Windows.Forms.MessageBoxButtons]::OK, $(if ($g2 -or $c2) { [Windows.Forms.MessageBoxIcon]::Information } else { [Windows.Forms.MessageBoxIcon]::Warning })) | Out-Null
  return $true
}
if (-not $SkipOffer) { Invoke-OfferInstall | Out-Null }
function Invoke-LightWipe {
  $protect = @('Realtek*','Microsoft Visual C++*','Microsoft Visual Studio* Redistributable*','Microsoft .NET*','Microsoft Edge WebView2*','Windows PC Health Check*','Update for *','Security Update*','Intel*','NVIDIA*','AMD*','Chipset*','Canon *','Google Chrome*','Grok Bot*','Windows Terminal*')
  $paths = @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')
  $changed = $false
  foreach ($prog in @(Get-ItemProperty $paths -ErrorAction SilentlyContinue)) {
    $dn = [string](Get-Prop $prog 'DisplayName'); if (-not $dn) { continue }
    $sc = Get-Prop $prog 'SystemComponent'
    if ($null -ne $sc) { try { if ([int]$sc -eq 1) { continue } } catch {} }
    if (Test-NameLike $dn $protect) { continue }
    $u = [string](Get-Prop $prog 'QuietUninstallString'); if (-not $u) { $u = [string](Get-Prop $prog 'UninstallString') }
    if (-not $u) { continue }
    try {
      if ($u -match '\{([0-9A-Fa-f-]{36})\}') {
        $p = Start-Process msiexec.exe -ArgumentList "/X{$($Matches[1])}", '/qn', '/norestart' -Wait -PassThru
        if ($p.ExitCode -in 0, 3010) { $changed = $true }
      }
    } catch {}
  }
  return $changed
}
$didWipe = $false
if (-not $SkipWipe -and ($Apply -or $UninstallNotKept)) { $didWipe = Invoke-LightWipe }
Write-Host "Log: $log"
if ($Restart -or ($RestartIfNeeded -and $didWipe)) { shutdown.exe /r /t 60 /c 'Admin-Setup finished.' }
