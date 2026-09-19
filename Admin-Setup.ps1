<#
.SYNOPSIS
  One script: desktop icon option, ask Grok Bot + Chrome, download+install on Yes, optional wipe, then restart.
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
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
function Test-IsAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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
function Install-DesktopIcon {
  $targetPs1 = if (Test-Path -LiteralPath $persist) { $persist } else { $self }
  if (-not $targetPs1) { throw 'Cannot find Admin-Setup.ps1 to pin as icon.' }
  $w = New-Object -ComObject WScript.Shell
  $folders = @([Environment]::GetFolderPath('Desktop'), (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'))
  $made = @()
  foreach ($folder in $folders) {
    if (-not $folder) { continue }
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $lnkPath = Join-Path $folder 'Admin Setup.lnk'
    $sc = $w.CreateShortcut($lnkPath)
    $sc.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$targetPs1`" -Apply -UninstallNotKept -RestartIfNeeded"
    $sc.WorkingDirectory = $homeRoot
    $sc.WindowStyle = 1
    $sc.Description = 'Admin Setup'
    $sc.IconLocation = "$env:SystemRoot\System32\imageres.dll,109"
    $sc.Save()
    try {
      $bytes = [IO.File]::ReadAllBytes($lnkPath)
      if ($bytes.Length -gt 0x15) { $bytes[0x15] = $bytes[0x15] -bor 0x20; [IO.File]::WriteAllBytes($lnkPath, $bytes) }
    } catch { Write-Log "Could not set RunAs on shortcut: $($_.Exception.Message)" }
    $made += $lnkPath
  }
  return $made
}
if (-not (Test-IsAdmin)) {
  Write-Log 'Re-launching elevated...'
  $arg = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$persist`"")
  if ($Apply) { $arg += '-Apply' }
  if ($UninstallNotKept) { $arg += '-UninstallNotKept' }
  if ($Restart) { $arg += '-Restart' }
  if ($RestartIfNeeded) { $arg += '-RestartIfNeeded' }
  if ($SkipWipe) { $arg += '-SkipWipe' }
  if ($SkipOffer) { $arg += '-SkipOffer' }
  if ($DesktopIcon) { $arg += '-DesktopIcon' }
  if ($SkipDesktopIcon) { $arg += '-SkipDesktopIcon' }
  if ($IconOnly) { $arg += '-IconOnly' }
  if ($ForceAsk) { $arg += '-ForceAsk' }
  Start-Process powershell.exe -Verb RunAs -ArgumentList $arg | Out-Null
  return
}
Write-Log "==== Admin-Setup start elevated=$(Test-IsAdmin) ===="
Add-Type -AssemblyName System.Windows.Forms | Out-Null
$wantIcon = $false
if ($IconOnly -or $DesktopIcon) { $wantIcon = $true }
elseif ($SkipDesktopIcon) { $wantIcon = $false }
else {
  $iconAsk = [Windows.Forms.MessageBox]::Show("Add an Admin Setup icon to the Desktop and Start menu?`r`n`r`nYes = one icon to run this bundle again (UAC / Run as admin).`r`nNo  = skip the icon.", 'Admin Setup — desktop icon', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Question)
  Write-Log "Desktop icon answer: $iconAsk"
  $wantIcon = ($iconAsk -eq [Windows.Forms.DialogResult]::Yes)
}
if ($wantIcon) {
  $icons = Install-DesktopIcon
  Write-Log ("Desktop/Start icon: " + ($icons -join '; '))
  Write-Host 'Desktop icon: Admin Setup'
  $icons | ForEach-Object { Write-Host "  $_" }
} else { Write-Host 'Desktop icon skipped.' }
if ($IconOnly) { Write-Host 'Icon only. Done.'; exit 0 }
function Test-NameLike([string]$Name, [string[]]$Patterns) { foreach ($p in $Patterns) { if ($Name -like $p) { return $true } }; return $false }
function Get-UninstallHits([string[]]$Patterns) {
  Get-ItemProperty @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*') -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -and (Test-NameLike $_.DisplayName $Patterns) }
}
function Test-GrokBotInstalled {
  $exes = @("$env:LOCALAPPDATA\Programs\Grok Bot\Grok Bot.exe","${env:ProgramFiles}\Grok Bot\Grok Bot.exe","${env:ProgramFiles(x86)}\Grok Bot\Grok Bot.exe")
  foreach ($e in $exes) { if ($e -and (Test-Path -LiteralPath $e)) { return $true } }
  return [bool](Get-UninstallHits @('Grok Bot*'))
}
function Test-ChromeInstalled {
  $exes = @("${env:ProgramFiles}\Google\Chrome\Application\chrome.exe","${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe","$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")
  foreach ($e in $exes) { if ($e -and (Test-Path -LiteralPath $e)) { return $true } }
  return [bool](Get-UninstallHits @('Google Chrome*'))
}
function Save-Url {
  param([string]$Url, [string]$Dest)
  New-Item -ItemType Directory -Force -Path (Split-Path $Dest) | Out-Null
  if (Test-Path -LiteralPath $Dest) { Remove-Item -LiteralPath $Dest -Force -ErrorAction SilentlyContinue }
  Write-Log "GET $Url -> $Dest"
  $ok = $false
  try { Start-BitsTransfer -Source $Url -Destination $Dest -ErrorAction Stop; $ok = $true } catch { Write-Log "BITS failed: $($_.Exception.Message)" }
  if (-not $ok) { try { Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -TimeoutSec 600; $ok = $true } catch { Write-Log "IWR failed: $($_.Exception.Message)" } }
  if (-not $ok) {
    try {
      $curl = "$env:SystemRoot\System32\curl.exe"
      if (Test-Path $curl) { & $curl -L --retry 3 --retry-delay 2 -o $Dest $Url; if ($LASTEXITCODE -eq 0) { $ok = $true } }
    } catch { Write-Log "curl failed: $($_.Exception.Message)" }
  }
  if (-not (Test-Path -LiteralPath $Dest)) { throw "Download produced no file: $Url" }
  $len = (Get-Item -LiteralPath $Dest).Length
  if ($len -lt 500KB) { throw "Download too small ($len bytes): $Url" }
  Write-Log "Saved $len bytes"
  return $Dest
}
function Get-GrokBotSetupInfo {
  $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'win32-arm64' } else { 'win32-x64' }
  $info = [pscustomobject]@{ Url = $null; Version = 'unknown' }
  foreach ($page in @('https://cursor.com/download/bot','https://www.cursor.com/download/bot')) {
    try {
      $html = (Invoke-WebRequest -Uri $page -UseBasicParsing -TimeoutSec 60).Content
      $re = "https://downloads\.cursor\.com/grokbot/stable/$arch/[^`"'\s<>]+\.exe"
      if ($html -match $re) {
        $info.Url = $Matches[0]
        if ($info.Url -match '/(\d+\.\d+\.\d+)/') { $info.Version = $Matches[1] }
        elseif ($info.Url -match 'Grok_Bot_(\d+\.\d+\.\d+)') { $info.Version = $Matches[1] }
        break
      }
    } catch { Write-Log "Grok page $page failed: $($_.Exception.Message)" }
  }
  if (-not $info.Url) {
    $info.Url = "https://downloads.cursor.com/grokbot/stable/$arch/0.47.0/Grok_Bot_0.47.0_Setup.exe"
    $info.Version = '0.47.0-fallback'
  }
  return $info
}
function Get-ChromeSetupInfo {
  [pscustomobject]@{ Url = 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi'; Fallback = 'https://dl.google.com/chrome/install/latest/chrome_installer.exe'; Version = 'latest-stable' }
}
function Install-GrokBot([string]$Url) {
  $dest = Join-Path $env:TEMP 'AdminSetup-Grok_Bot_Setup.exe'
  Write-Host 'Downloading Grok Bot...'
  Save-Url -Url $Url -Dest $dest | Out-Null
  Write-Host 'Installing Grok Bot...'
  $p = Start-Process -FilePath $dest -ArgumentList '/S' -PassThru -Wait
  if ($null -eq $p.ExitCode -or $p.ExitCode -notin @(0, 1)) { $p = Start-Process -FilePath $dest -PassThru -Wait }
  return $p.ExitCode
}
function Install-Chrome($Info) {
  $dir = Join-Path $env:TEMP 'AdminSetup-Chrome'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
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
  $caption = 'Admin Setup — Grok Bot + Chrome'
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
  $programs = Get-ItemProperty $paths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -and ($null -eq $_.SystemComponent -or [int]$_.SystemComponent -ne 1) }
  foreach ($prog in $programs) {
    if (Test-NameLike $prog.DisplayName $protect) { continue }
    $u = $prog.QuietUninstallString; if (-not $u) { $u = $prog.UninstallString }; if (-not $u) { continue }
    try {
      if ($u -match '\{([0-9A-Fa-f-]{36})\}') {
        $p = Start-Process msiexec.exe -ArgumentList "/X{$($Matches[1])}", '/qn', '/norestart' -Wait -PassThru
        if ($p.ExitCode -in 0, 3010) { $changed = $true }
      } elseif ($prog.QuietUninstallString) {
        Start-Process cmd.exe -ArgumentList '/c', $prog.QuietUninstallString -Wait -WindowStyle Hidden | Out-Null
        $changed = $true
      }
    } catch { Write-Log "Uninstall failed $($prog.DisplayName): $($_.Exception.Message)" }
  }
  return $changed
}
$didWipe = $false
if (-not $SkipWipe -and ($Apply -or $UninstallNotKept)) { $didWipe = Invoke-LightWipe }
Write-Host "Log: $log"
$reboot = $false
if ($Restart) { $reboot = $true } elseif ($RestartIfNeeded -and $didWipe) { $reboot = $true }
if ($reboot) { shutdown.exe /r /t 60 /c 'Admin-Setup finished (apps already offered/installed).' }
