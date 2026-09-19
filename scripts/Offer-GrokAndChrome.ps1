<#
.SYNOPSIS
  After wipe restart: offer latest Grok Bot + Google Chrome; install and pin if Yes.

.DESCRIPTION
  Run once at logon (RunOnce registered by Admin-Setup / Cleanup).
  1) Resolve latest Grok Bot (cursor.com/download/bot) and Chrome (Google offline/enterprise).
  2) MessageBox Yes/No naming both.
  3) On Yes: download + install both, then pin Chrome + Grok Bot on the taskbar.
  4) On No: exit; taskbar stays Start-only from the wipe pass.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Offer-GrokAndChrome.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Offer-GrokAndChrome.ps1 -RegisterRunOnce
#>
[CmdletBinding()]
param(
  [switch]$RegisterRunOnce,
  [switch]$ForceAsk,
  [switch]$SkipPin
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $here 'Offer-GrokAndChrome.log'

function Write-Log([string]$m) {
  $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $m
  New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
  $line | Tee-Object -FilePath $log -Append
}

function Test-AppInstalled {
  param([string[]]$NamePatterns, [string[]]$ExePaths)
  foreach ($pat in $NamePatterns) {
    $hit = Get-ItemProperty @(
      'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
      'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
      'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    ) -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -and ($_.DisplayName -like $pat) }
    if ($hit) { return $true }
  }
  foreach ($c in $ExePaths) { if ($c -and (Test-Path $c)) { return $true } }
  return $false
}

function Test-GrokBotInstalled {
  Test-AppInstalled -NamePatterns @('*Grok Bot*','Grok') -ExePaths @(
    "$env:LOCALAPPDATA\Programs\Grok Bot\Grok Bot.exe",
    "${env:ProgramFiles}\Grok Bot\Grok Bot.exe",
    "${env:ProgramFiles(x86)}\Grok Bot\Grok Bot.exe"
  )
}

function Test-ChromeInstalled {
  Test-AppInstalled -NamePatterns @('Google Chrome*') -ExePaths @(
    "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
  )
}

function Register-OfferRunOnce {
  $ps1 = Join-Path $here 'Offer-GrokAndChrome.ps1'
  $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File `"$ps1`""
  $runOnce = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
  if (-not (Test-Path $runOnce)) { New-Item -Path $runOnce -Force | Out-Null }
  New-ItemProperty -Path $runOnce -Name 'AdminSetupOfferGrokChrome' -PropertyType String -Value $cmd -Force | Out-Null
  # Clear old Grok-only RunOnce name if present
  Remove-ItemProperty -Path $runOnce -Name 'AdminSetupOfferGrokBot' -ErrorAction SilentlyContinue
  Write-Log 'Registered RunOnce AdminSetupOfferGrokChrome'
  Write-Host 'Registered: offer Grok Bot + Chrome at next logon.'
}

function Get-GrokBotSetupInfo {
  $info = [pscustomobject]@{ Url = $null; Version = 'unknown' }
  try {
    $html = (Invoke-WebRequest -Uri 'https://cursor.com/download/bot' -UseBasicParsing -TimeoutSec 60).Content
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'win32-arm64' } else { 'win32-x64' }
    $re = "https://downloads\.cursor\.com/grokbot/stable/$arch/[^`"\s<>]+\.exe"
    if ($html -match $re) {
      $info.Url = $Matches[0]
      if ($info.Url -match '/(\d+\.\d+\.\d+)/') { $info.Version = $Matches[1] }
      elseif ($info.Url -match 'Grok_Bot_(\d+\.\d+\.\d+)') { $info.Version = $Matches[1] }
    }
  } catch {
    Write-Log "Grok resolve failed: $($_.Exception.Message)"
  }
  if (-not $info.Url) {
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'win32-arm64' } else { 'win32-x64' }
    $info.Url = "https://downloads.cursor.com/grokbot/stable/$arch/0.57.1/Grok_Bot_0.57.1_Setup.exe"
    $info.Version = '0.57.1'
    Write-Log "Grok fallback URL $($info.Url)"
  }
  return $info
}

function Get-ChromeSetupInfo {
  # Official 64-bit offline enterprise MSI (stable). Version resolved from Content-Disposition / filename when possible.
  $info = [pscustomobject]@{
    Url     = 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi'
    Version = 'latest-stable'
    Kind    = 'msi'
  }
  try {
    $req = [System.Net.HttpWebRequest]::Create($info.Url)
    $req.Method = 'HEAD'
    $req.AllowAutoRedirect = $true
    $req.Timeout = 60000
    $resp = $req.GetResponse()
    $cd = $resp.Headers['Content-Disposition']
    $resp.Close()
    if ($cd -and $cd -match '(\d+\.\d+\.\d+\.\d+)') { $info.Version = $Matches[1] }
  } catch {
    Write-Log "Chrome HEAD failed (ok): $($_.Exception.Message)"
  }
  return $info
}

function Install-GrokBot([string]$Url) {
  $destDir = Join-Path $env:TEMP 'AdminSetup-GrokBot'
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  $dest = Join-Path $destDir 'Grok_Bot_Setup.exe'
  Write-Host 'Downloading Grok Bot...'
  Invoke-WebRequest -Uri $Url -OutFile $dest -UseBasicParsing -TimeoutSec 600
  if (-not (Test-Path $dest) -or ((Get-Item $dest).Length -lt 1MB)) {
    throw "Grok download failed or too small: $dest"
  }
  Write-Log "Grok downloaded $((Get-Item $dest).Length) bytes"
  Write-Host 'Installing Grok Bot...'
  # NSIS-style silent when supported
  $p = Start-Process -FilePath $dest -ArgumentList '/S' -PassThru -Wait
  if ($null -eq $p.ExitCode -or $p.ExitCode -notin @(0, 1)) {
    Write-Log "Grok /S exit=$($p.ExitCode) — retry interactive"
    $p = Start-Process -FilePath $dest -PassThru -Wait
  }
  Write-Log "Grok installer exit=$($p.ExitCode)"
  return $p.ExitCode
}

function Install-Chrome([string]$Url, [string]$Kind) {
  $destDir = Join-Path $env:TEMP 'AdminSetup-Chrome'
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  if ($Kind -eq 'msi') {
    $dest = Join-Path $destDir 'ChromeEnterprise64.msi'
    Write-Host 'Downloading Google Chrome...'
    Invoke-WebRequest -Uri $Url -OutFile $dest -UseBasicParsing -TimeoutSec 600
    if (-not (Test-Path $dest) -or ((Get-Item $dest).Length -lt 1MB)) {
      throw "Chrome download failed or too small: $dest"
    }
    Write-Log "Chrome downloaded $((Get-Item $dest).Length) bytes"
    Write-Host 'Installing Google Chrome...'
    $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', "`"$dest`"", '/qn', '/norestart') -PassThru -Wait
    Write-Log "Chrome msiexec exit=$($p.ExitCode)"
    return $p.ExitCode
  }
  throw "Unsupported Chrome kind: $Kind"
}

function Invoke-PinChromeAndGrok {
  $taskbar = Join-Path $here 'Minimal-Taskbar.ps1'
  if (-not (Test-Path $taskbar)) {
    Write-Log "Missing Minimal-Taskbar.ps1 — skip pin"
    return
  }
  Write-Host 'Pinning Chrome + Grok Bot to the taskbar...'
  $args = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $taskbar,
    '-Apply', '-DockChromeGrok', '-SkipWindhawkTray'
  )
  $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Wait -PassThru -NoNewWindow
  Write-Log "Pin exit=$($p.ExitCode)"
}

if ($RegisterRunOnce) {
  Register-OfferRunOnce
  exit 0
}

Add-Type -AssemblyName System.Windows.Forms | Out-Null
Write-Log '==== Offer-GrokAndChrome start ===='

$grokHave = Test-GrokBotInstalled
$chromeHave = Test-ChromeInstalled
Write-Log "GrokInstalled=$grokHave ChromeInstalled=$chromeHave ForceAsk=$ForceAsk"

if ($grokHave -and $chromeHave -and -not $ForceAsk) {
  Write-Log 'Both already installed — skip ask'
  if (-not $SkipPin) { Invoke-PinChromeAndGrok }
  exit 0
}

Write-Host 'Checking latest Grok Bot and Chrome...'
$grok = Get-GrokBotSetupInfo
$chrome = Get-ChromeSetupInfo
Write-Log "Grok latest=$($grok.Version) url=$($grok.Url)"
Write-Log "Chrome latest=$($chrome.Version) url=$($chrome.Url)"

$needGrok = (-not $grokHave) -or $ForceAsk
$needChrome = (-not $chromeHave) -or $ForceAsk
$lines = @()
$lines += 'This PC was cleaned. Install the latest apps?'
$lines += ''
if ($needGrok) { $lines += ("- Grok Bot  " + $grok.Version) } else { $lines += '- Grok Bot  (already installed)' }
if ($needChrome) { $lines += ("- Google Chrome  " + $chrome.Version) } else { $lines += '- Google Chrome  (already installed)' }
$lines += ''
$lines += 'Yes = download, install, and pin both on the taskbar.'
$msg = $lines -join "`r`n"
$caption = 'Admin setup — Grok Bot + Chrome'
$result = [System.Windows.Forms.MessageBox]::Show(
  $msg,
  $caption,
  [System.Windows.Forms.MessageBoxButtons]::YesNo,
  [System.Windows.Forms.MessageBoxIcon]::Question
)
Write-Log "User answer: $result"

if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
  Write-Log 'User declined'
  exit 0
}

$errors = New-Object System.Collections.Generic.List[string]
try {
  if ($needGrok) {
    $code = Install-GrokBot -Url $grok.Url
    if ($code -notin 0, 1, $null) { $errors.Add("Grok Bot exit $code") }
  }
  if ($needChrome) {
    $code = Install-Chrome -Url $chrome.Url -Kind $chrome.Kind
    if ($code -notin 0, 3010, $null) { $errors.Add("Chrome exit $code") }
  }
  Start-Sleep -Seconds 2
  if (-not $SkipPin) { Invoke-PinChromeAndGrok }

  if ($errors.Count -gt 0) {
    [System.Windows.Forms.MessageBox]::Show(
      ("Finished with warnings:`r`n" + ($errors -join "`r`n")),
      $caption,
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
    exit 2
  }
  [System.Windows.Forms.MessageBox]::Show(
    'Grok Bot and Chrome are ready (pinned when shortcuts were found).',
    $caption,
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
  ) | Out-Null
  exit 0
} catch {
  Write-Log "ERROR $($_.Exception.Message)"
  [System.Windows.Forms.MessageBox]::Show(
    ("Could not finish install:`r`n" + $_.Exception.Message),
    $caption,
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Error
  ) | Out-Null
  Start-Process 'https://cursor.com/download/bot'
  Start-Process 'https://www.google.com/chrome/'
  exit 1
}
