<#
.SYNOPSIS
  After cleanup restart: ask to download Grok Bot if it is not installed.

.DESCRIPTION
  Designed to run once at logon (RunOnce / scheduled by Admin-Setup or Cleanup).
  - If Grok Bot is already installed: exit quietly.
  - If missing: MessageBox Yes/No "Download Grok Bot?"
  - On Yes: resolve current Windows installer from cursor.com/download/bot, download, run Setup.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Offer-GrokBot.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Offer-GrokBot.ps1 -RegisterRunOnce
#>
[CmdletBinding()]
param(
  [switch]$RegisterRunOnce,
  [switch]$ForceAsk
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $here 'Offer-GrokBot.log'

function Write-Log([string]$m) {
  $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $m
  New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
  $line | Tee-Object -FilePath $log -Append
}

function Test-GrokBotInstalled {
  $names = @('Grok Bot', 'GrokBot', 'Grok')
  foreach ($n in $names) {
    $p = Get-Package -Name "*$n*" -ErrorAction SilentlyContinue
    if ($p) { return $true }
  }
  $paths = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
  $hit = Get-ItemProperty $paths -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -and ($_.DisplayName -like '*Grok Bot*' -or $_.DisplayName -eq 'Grok') }
  if ($hit) { return $true }
  $candidates = @(
    "$env:LOCALAPPDATA\Programs\Grok Bot\Grok Bot.exe",
    "$env:LOCALAPPDATA\Programs\grok-bot\Grok Bot.exe",
    "$env:LOCALAPPDATA\Grok Bot\Grok Bot.exe"
  )
  foreach ($c in $candidates) { if (Test-Path $c) { return $true } }
  $sm = @(
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Grok Bot.lnk",
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Grok Bot.lnk"
  )
  foreach ($s in $sm) { if (Test-Path $s) { return $true } }
  return $false
}

function Register-OfferRunOnce {
  $ps1 = Join-Path $here 'Offer-GrokBot.ps1'
  $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File `"$ps1`""
  $runOnce = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
  if (-not (Test-Path $runOnce)) { New-Item -Path $runOnce -Force | Out-Null }
  New-ItemProperty -Path $runOnce -Name 'AdminSetupOfferGrokBot' -PropertyType String -Value $cmd -Force | Out-Null
  Write-Log "Registered RunOnce AdminSetupOfferGrokBot"
  Write-Host 'Registered: ask to download Grok Bot at next logon if missing.'
}

function Get-GrokBotSetupUrl {
  try {
    $html = (Invoke-WebRequest -Uri 'https://cursor.com/download/bot' -UseBasicParsing -TimeoutSec 60).Content
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
      if ($html -match 'https://downloads\.cursor\.com/grokbot/stable/win32-arm64/[^"\s<>]+\.exe') {
        return $Matches[0]
      }
    } else {
      if ($html -match 'https://downloads\.cursor\.com/grokbot/stable/win32-x64/[^"\s<>]+\.exe') {
        return $Matches[0]
      }
    }
  } catch {
    Write-Log "Resolve URL failed: $($_.Exception.Message)"
  }
  # Fallback known stable path pattern (may lag latest)
  if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
    return 'https://downloads.cursor.com/grokbot/stable/win32-arm64/0.56.1/Grok_Bot_0.56.1_Setup.exe'
  }
  return 'https://downloads.cursor.com/grokbot/stable/win32-x64/0.56.1/Grok_Bot_0.56.1_Setup.exe'
}

function Install-GrokBot {
  $url = Get-GrokBotSetupUrl
  Write-Log "Download URL: $url"
  $destDir = Join-Path $env:TEMP 'AdminSetup-GrokBot'
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  $dest = Join-Path $destDir 'Grok_Bot_Setup.exe'
  Write-Host "Downloading Grok Bot..."
  Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 600
  if (-not (Test-Path $dest) -or ((Get-Item $dest).Length -lt 1MB)) {
    throw "Download failed or file too small: $dest"
  }
  Write-Log "Downloaded $((Get-Item $dest).Length) bytes -> $dest"
  Write-Host "Starting installer..."
  $p = Start-Process -FilePath $dest -PassThru -Wait
  Write-Log "Installer exit=$($p.ExitCode)"
  return $p.ExitCode
}

if ($RegisterRunOnce) {
  Register-OfferRunOnce
  exit 0
}

Add-Type -AssemblyName System.Windows.Forms | Out-Null
Write-Log '==== Offer-GrokBot start ===='

$installed = Test-GrokBotInstalled
Write-Log "Installed=$installed ForceAsk=$ForceAsk"

if ($installed -and -not $ForceAsk) {
  Write-Log 'Grok Bot already present — skip ask'
  exit 0
}

$msg = if ($installed) {
  'Grok Bot looks installed. Open download page / reinstall anyway?'
} else {
  "Grok Bot is not installed on this PC.`r`n`r`nDownload and install it now from cursor.com?"
}
$caption = 'Admin setup — Grok Bot'
$result = [System.Windows.Forms.MessageBox]::Show(
  $msg,
  $caption,
  [System.Windows.Forms.MessageBoxButtons]::YesNo,
  [System.Windows.Forms.MessageBoxIcon]::Question
)
Write-Log "User answer: $result"

if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
  Write-Log 'User declined download'
  exit 0
}

try {
  $code = Install-GrokBot
  if ($code -notin 0, $null) {
    [System.Windows.Forms.MessageBox]::Show(
      "Installer finished with exit code $code. If Grok Bot did not appear, open https://cursor.com/download/bot",
      $caption,
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
    exit 2
  }
  [System.Windows.Forms.MessageBox]::Show(
    'Grok Bot installer finished. You can sign in from the Start menu.',
    $caption,
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
  ) | Out-Null
  exit 0
} catch {
  Write-Log "ERROR $($_.Exception.Message)"
  [System.Windows.Forms.MessageBox]::Show(
    "Could not download/install Grok Bot:`r`n$($_.Exception.Message)`r`n`r`nOpen https://cursor.com/download/bot manually.",
    $caption,
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Error
  ) | Out-Null
  Start-Process 'https://cursor.com/download/bot'
  exit 1
}
