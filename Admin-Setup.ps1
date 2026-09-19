<#
.SYNOPSIS
  Wipe other drives, then C: (keep Windows), delete C:\Users, Recycle last.
  Before reboot: info alert explaining the wipe only (no download ask).
  After restart (once): offer Developers Preference (Chrome, Grok Bot, Snipping Tool).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Admin-Setup.ps1 -Mode Wipe -ConfirmPhrase WIPE-ALL-DATA
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Admin-Setup.ps1 -Mode Offer
#>
[CmdletBinding()]
param(
  [ValidateSet('All','HideBar','Badges','Wipe','Offer')]
  [string]$Mode = 'Wipe',
  [string]$ConfirmPhrase = ''
)
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'
# Survive Users wipe
$script:AdminDir = 'C:\ProgramData\AdminSetup'
$script:Live = ($ConfirmPhrase -eq 'WIPE-ALL-DATA')
$script:Done = 0; $script:Total = 1; $script:T0 = Get-Date
$script:Bar = $null; $script:Lbl = $null; $script:Eta = $null; $script:Win = $null

function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function L([string]$m) {
  New-Item -ItemType Directory -Force -Path $script:AdminDir | Out-Null
  $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $m
  Add-Content (Join-Path $script:AdminDir 'Admin-Setup.log') $line
  Write-Host $line
}
function Is-Blocked([string]$Name) {
  $n = "$Name".ToLowerInvariant()
  return @('system volume information','$recycle.bin','pagefile.sys','hiberfil.sys','swapfile.sys','windows','boot','bootmgr','recovery','$winreagent','programdata') -contains $n
}
function Show-Bar {
  Add-Type -AssemblyName System.Windows.Forms, System.Drawing
  $w = New-Object System.Windows.Forms.Form
  $w.Text = 'Wipe in progress'
  $w.Size = New-Object System.Drawing.Size(640,150)
  $w.StartPosition = 'CenterScreen'
  $w.TopMost = $true
  $l = New-Object System.Windows.Forms.Label; $l.SetBounds(12,10,600,36)
  $e = New-Object System.Windows.Forms.Label; $e.SetBounds(12,48,600,20)
  $p = New-Object System.Windows.Forms.ProgressBar; $p.SetBounds(12,74,600,24); $p.Maximum = 100
  $w.Controls.AddRange(@($l,$e,$p)); $w.Show(); $w.Refresh()
  $script:Win = $w; $script:Lbl = $l; $script:Eta = $e; $script:Bar = $p
}
function Tick([string]$Path) {
  $script:Done++
  $pct = [Math]::Min(100,[int](100.0 * $script:Done / [Math]::Max(1,$script:Total)))
  $el = ((Get-Date) - $script:T0).TotalSeconds
  $rem = 0
  if ($script:Done -gt 0) { $rem = ($el / $script:Done) * ($script:Total - $script:Done) }
  $msg = '{0}/{1} {2}% {3}' -f $script:Done,$script:Total,$pct,$Path
  Write-Host $msg
  if ($script:Lbl) { $script:Lbl.Text = $msg }
  if ($script:Eta) { $script:Eta.Text = ('elapsed {0:n0}s   eta {1:n0}s' -f $el,[Math]::Max(0,$rem)) }
  if ($script:Bar) { $script:Bar.Value = $pct }
  if ($script:Win) { $script:Win.Refresh(); [System.Windows.Forms.Application]::DoEvents() }
}
function Kill-Fast([string]$Path) {
  $leaf = [IO.Path]::GetFileName($Path)
  if (Is-Blocked $leaf) { L "SKIP $Path"; Tick "SKIP $leaf"; return }
  if ($Path -like 'C:\ProgramData\AdminSetup*') { L "SKIP $Path"; Tick 'SKIP AdminSetup'; return }
  L "DELETE $Path"
  if ($script:Live) {
    try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop } catch {
      cmd /c "rd /s /q `"$Path`""
      cmd /c "del /f /q `"$Path`""
    }
  }
  if (Test-Path -LiteralPath $Path) { L "LEFT $Path" } else { L "GONE $Path" }
  Tick $Path
}
function List-Kids([string]$Root) {
  $out = @()
  if (-not (Test-Path -LiteralPath $Root)) { return $out }
  cmd /c "dir /a /b `"$Root`"" | ForEach-Object {
    if ($_ -and -not (Is-Blocked $_)) { $out += (Join-Path $Root $_) }
  }
  return $out
}
function Invoke-Wipe {
  $os = $env:SystemDrive.TrimEnd(':')
  $jobs = @()
  Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -in 2,3 } | ForEach-Object {
    $let = $_.DeviceID.TrimEnd(':')
    if ($let -eq $os) { return }
    $jobs += List-Kids ($let + ':\')
  }
  $jobs += List-Kids ($os + ':\') | Where-Object { [IO.Path]::GetFileName($_).ToLowerInvariant() -ne 'users' }
  $jobs += List-Kids ($os + ':\Users')
  $script:Total = [Math]::Max(1, $jobs.Count)
  $script:Done = 0; $script:T0 = Get-Date
  Show-Bar
  L "jobs=$($script:Total) live=$($script:Live)"
  $osRoot = ($os + ':\').ToLowerInvariant()
  foreach ($p in $jobs) { if (-not $p.ToLowerInvariant().StartsWith($osRoot)) { Kill-Fast $p } }
  foreach ($p in $jobs) { if ($p.ToLowerInvariant().StartsWith($osRoot)) { Kill-Fast $p } }
  if ($script:Live) { try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {} }
  if ($script:Bar) { $script:Bar.Value = 100 }
  if ($script:Win) { Start-Sleep 1; $script:Win.Close() }
  L 'WIPE DONE'
}
function Show-WipeExplainer {
  Add-Type -AssemblyName System.Windows.Forms
  [void][System.Windows.Forms.MessageBox]::Show(
    ("Wipe finished." + [Environment]::NewLine + [Environment]::NewLine +
     "This PC removed removable files and apps (Windows itself was kept)." + [Environment]::NewLine + [Environment]::NewLine +
     "The computer will restart now." + [Environment]::NewLine +
     "After you sign in, you will be asked once whether to install the Developers Preference package (Chrome, Grok Bot, Snipping Tool)."),
    'Admin Setup — wipe complete',
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
  )
  L 'Showed wipe explainer (no download ask)'
}
function Try-Winget([string]$Id) {
  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if (-not $winget) { return $false }
  L "WINGET $Id"
  & winget install -e --id $Id --accept-package-agreements --accept-source-agreements --disable-interactivity
  return ($LASTEXITCODE -eq 0)
}
function Test-ChromeInstalled {
  foreach ($p in @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
  )) { if (Test-Path $p) { return $true } }
  return $false
}
function Install-LatestChrome {
  $ProgressPreference = 'SilentlyContinue'
  try {
    if ((Try-Winget 'Google.Chrome') -and (Test-ChromeInstalled)) { L 'CHROME winget ok'; return }
  } catch { L "CHROME winget: $_" }
  $temp = $env:TEMP; if (-not $temp) { $temp = Join-Path $env:USERPROFILE 'Downloads' }
  New-Item -ItemType Directory -Force -Path $temp | Out-Null
  $exe = Join-Path $temp 'chrome_installer.exe'
  try {
    Invoke-WebRequest -Uri 'https://dl.google.com/chrome/install/latest/chrome_installer.exe' -OutFile $exe -UseBasicParsing
    Start-Process -FilePath $exe -Wait
    if (Test-ChromeInstalled) { L 'CHROME ok'; return }
  } catch { L "CHROME consumer fail: $_" }
  try {
    $msi = Join-Path $temp 'Chrome64.msi'
    Invoke-WebRequest 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi' -OutFile $msi -UseBasicParsing
    Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn" -Wait
    L 'CHROME msi done'
  } catch { L "CHROME msi fail: $_" }
}
function Install-GrokBot {
  try {
    $html = (Invoke-WebRequest 'https://cursor.com/download/bot' -UseBasicParsing -TimeoutSec 60).Content
    if ($html -match 'https://downloads\.cursor\.com/grokbot/stable/win32-x64/[^"\s<>]+\.exe') {
      $url = $Matches[0]
      $dest = Join-Path $env:TEMP 'Grok_Bot_Setup.exe'
      L "GROK download $url"
      Invoke-WebRequest $url -OutFile $dest -UseBasicParsing -TimeoutSec 600
      Start-Process $dest -ArgumentList '/S' -Wait
      L 'GROK installed'
      return
    }
  } catch { L "GROK download: $($_.Exception.Message)" }
  if (Try-Winget 'xAI.GrokBuild') { L 'GROK winget ok' } else {
    L 'GROK miss; open download page'
    Start-Process 'https://cursor.com/download/bot'
  }
}
function Install-SnippingTool {
  if (Try-Winget '9MZ95KL8MR0L') { L 'SNIP winget ok' } else { L 'SNIP winget miss' }
  foreach ($exe in @(
    "$env:SystemRoot\System32\SnippingTool.exe",
    "$env:SystemRoot\System32\ScreenSketch.exe"
  )) {
    if (Test-Path $exe) { Start-Process $exe; return }
  }
  try { Start-Process 'ms-screenclip:' } catch {}
}
function Offer-DevPref {
  # Single-flight: prevent two RunOnce / two windows
  $m = New-Object System.Threading.Mutex($false, 'Global\AdminSetupDevPrefOffer')
  if (-not $m.WaitOne(0, $false)) {
    L 'DEVPREF already running — skip duplicate window'
    return
  }
  try {
    Add-Type -AssemblyName System.Windows.Forms
    $r = [System.Windows.Forms.MessageBox]::Show(
      ('Install Developers Preference package?' + [Environment]::NewLine + [Environment]::NewLine +
       'Latest Chrome, Grok Bot, and Snipping Tool.'),
      'Developers Preference',
      [System.Windows.Forms.MessageBoxButtons]::YesNo,
      [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { L 'DEVPREF declined'; return }
    L 'DEVPREF yes'
    Install-LatestChrome
    Install-GrokBot
    Install-SnippingTool
    L 'DEVPREF done'
  } finally {
    $m.ReleaseMutex() | Out-Null
    $m.Dispose()
  }
}
function Register-OfferAfterRestart {
  $self = Join-Path $script:AdminDir 'Admin-Setup.ps1'
  # ONE RunOnce only (HKLM) — HKCU+HKLM caused two windows
  $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File `"$self`" -Mode Offer"
  $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
  New-Item -Path $key -Force -EA SilentlyContinue | Out-Null
  # Clear any old duplicate names
  foreach ($n in @('AdminSetupDevPrefOffer','AdminSetupOfferGrokChrome','AdminSetupOfferGrokBot')) {
    Remove-ItemProperty -Path $key -Name $n -EA SilentlyContinue
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name $n -EA SilentlyContinue
  }
  New-ItemProperty -Path $key -Name 'AdminSetupDevPrefOffer' -PropertyType String -Value $cmd -Force | Out-Null
  L 'Registered single HKLM RunOnce for Offer after restart'
}
function Persist-Self {
  New-Item -ItemType Directory -Force -Path $script:AdminDir | Out-Null
  if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
    Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $script:AdminDir 'Admin-Setup.ps1') -Force
  }
}

if ($Mode -eq 'HideBar') { return }
if ($Mode -eq 'Badges') { return }
if ($Mode -eq 'Offer') {
  Offer-DevPref
  L 'OFFER DONE'
  return
}

if (-not (Test-Admin)) {
  $self = $PSCommandPath
  if (-not $self) { $self = Join-Path $script:AdminDir 'Admin-Setup.ps1' }
  # Re-launch elevated once (no extra cmd.exe wrapper)
  Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$self`" -Mode $Mode -ConfirmPhrase $ConfirmPhrase"
  return
}

Persist-Self
Register-OfferAfterRestart
Invoke-Wipe
Show-WipeExplainer
L 'Scheduling restart — Dev Preference ask only after sign-in'
shutdown.exe /r /t 30 /c "Wipe complete. After sign-in you will be asked about Developers Preference."
L 'DONE'
