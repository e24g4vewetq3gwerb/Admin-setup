<#
.SYNOPSIS
  Minimal dock-style taskbar: only Chrome, Cursor, and Grok Bot; hide widgets/search/task view and overflow tray icons.

.DESCRIPTION
  - Hides Widgets/weather, Search, Task View, Chat/Copilot
  - Centers taskbar icons
  - Hides everything under the system-tray overflow chevron (NoTrayItemsDisplay + IsPromoted=0)
  - Keeps pin shortcuts for Chrome, Cursor, Grok Bot only
  Does not auto-hide the whole taskbar (apps stay visible).

  -Audit   Report only (default)
  -Apply   Write registry + clean pins + restart Explorer
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [switch]$Audit,
  [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
if (-not $Audit -and -not $Apply) { $Audit = $true }

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $here 'Minimal-Taskbar.log'
$csv = Join-Path $here 'Minimal-Taskbar.csv'
$results = New-Object System.Collections.Generic.List[object]

function L([string]$m) {
  $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $m
  $line | Tee-Object -FilePath $log -Append
}
function Add-R([string]$Item, [string]$Status, [string]$Detail) {
  $results.Add([pscustomobject]@{ Item = $Item; Status = $Status; Detail = $Detail })
  L "[$Status] $Item — $Detail"
}

function Get-RegInt([string]$Path, [string]$Name) {
  try {
    if (-not (Test-Path $Path)) { return $null }
    $v = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
    if ($null -eq $v) { return $null }
    return [int]$v
  } catch { return $null }
}

function Set-RegDword([string]$Path, [string]$Name, [int]$Value, [string]$Label) {
  $cur = Get-RegInt $Path $Name
  if ($Audit) {
    $want = if ($cur -eq $Value) { 'OK' } else { 'NEED' }
    Add-R $Label $want "current=$cur want=$Value"
    return
  }
  if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
  if ($PSCmdlet.ShouldProcess("$Path\$Name", "Set $Value")) {
    New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
    Add-R $Label 'FIXED' "set $Value (was $cur)"
  }
}

L "==== Minimal-Taskbar Audit=$Audit Apply=$Apply ===="

$adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$search = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
$feeds = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds'
$pol = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
$nis = 'HKCU:\Control Panel\NotifyIconSettings'

Set-RegDword $adv 'TaskbarDa' 0 'Widgets/weather button'
Set-RegDword $adv 'ShowTaskViewButton' 0 'Task View button'
Set-RegDword $adv 'TaskbarMn' 0 'Chat button'
Set-RegDword $adv 'ShowCopilotButton' 0 'Copilot button'
Set-RegDword $adv 'TaskbarAl' 1 'Taskbar center align'
Set-RegDword $search 'SearchboxTaskbarMode' 0 'Search box hidden'
Set-RegDword $feeds 'ShellFeedsTaskbarViewMode' 2 'News and interests hidden'
Set-RegDword $pol 'NoTrayItemsDisplay' 1 'Hide overflow tray icons (chevron)'

# Other system tray icons -> Off
if (Test-Path $nis) {
  $keys = @(Get-ChildItem $nis)
  $bad = 0
  foreach ($k in $keys) {
    $p = Get-RegInt $k.PSPath 'IsPromoted'
    if ($p -ne 0) { $bad++ }
  }
  if ($Audit) {
    Add-R 'NotifyIconSettings' $(if ($bad -eq 0) { 'OK' } else { 'NEED' }) "icons=$($keys.Count) notOff=$bad"
  } else {
    foreach ($k in $keys) {
      New-ItemProperty -Path $k.PSPath -Name 'IsPromoted' -PropertyType DWord -Value 0 -Force | Out-Null
    }
    Add-R 'NotifyIconSettings' 'FIXED' "IsPromoted=0 for $($keys.Count) icons"
  }
} else {
  Add-R 'NotifyIconSettings' 'OK' 'key missing (nothing to hide)'
}

# Widgets policy (machine)
if (-not $Audit) {
  try {
    New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Name 'AllowNewsAndInterests' -PropertyType DWord -Value 0 -Force | Out-Null
    Add-R 'Dsh AllowNewsAndInterests' 'FIXED' '0'
  } catch {
    Add-R 'Dsh AllowNewsAndInterests' 'NEED' $_.Exception.Message
  }
}

# Pin folder: only Chrome / Cursor / Grok Bot shortcuts
$pinDir = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
$keepNames = @('Google Chrome.lnk', 'Cursor.lnk', 'Grok Bot.lnk')
$sources = @{
  'Google Chrome.lnk' = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk"
  'Cursor.lnk'        = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Cursor.lnk"
  'Grok Bot.lnk'      = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Grok Bot.lnk"
}

if ($Audit) {
  $extra = @()
  if (Test-Path $pinDir) {
    $extra = @(Get-ChildItem $pinDir -Filter '*.lnk' -ErrorAction SilentlyContinue |
      Where-Object { $keepNames -notcontains $_.Name } |
      Select-Object -ExpandProperty Name)
  }
  $missing = @($keepNames | Where-Object { -not (Test-Path (Join-Path $pinDir $_)) })
  Add-R 'TaskBar pin folder' $(if ($extra.Count -eq 0 -and $missing.Count -eq 0) { 'OK' } else { 'NEED' }) "extra=$($extra -join ';') missing=$($missing -join ';')"
} else {
  New-Item -ItemType Directory -Force -Path $pinDir | Out-Null
  Get-ChildItem $pinDir -Filter '*.lnk' -ErrorAction SilentlyContinue | ForEach-Object {
    if ($keepNames -notcontains $_.Name) {
      Remove-Item $_.FullName -Force
      Add-R "Remove pin $($_.Name)" 'FIXED' 'removed'
    }
  }
  foreach ($name in $keepNames) {
    $src = $sources[$name]
    if (Test-Path $src) {
      Copy-Item $src (Join-Path $pinDir $name) -Force
      Add-R "Pin shortcut $name" 'FIXED' 'copied'
    } else {
      Add-R "Pin shortcut $name" 'NEED' "source missing: $src"
    }
  }
  # Clear Taskband favorites so Explorer rebuilds from pin folder where possible
  try {
    $tb = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband'
    if (Test-Path $tb) {
      Remove-ItemProperty -Path $tb -Name 'Favorites' -Force -ErrorAction SilentlyContinue
      Remove-ItemProperty -Path $tb -Name 'FavoritesResolve' -Force -ErrorAction SilentlyContinue
    }
    Add-R 'Taskband Favorites clear' 'FIXED' 'cleared'
  } catch {
    Add-R 'Taskband Favorites clear' 'NEED' $_.Exception.Message
  }
  $tray = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\TrayNotify'
  if (Test-Path $tray) {
    Remove-ItemProperty -Path $tray -Name 'IconStreams' -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $tray -Name 'PastIconsStream' -Force -ErrorAction SilentlyContinue
    Add-R 'TrayNotify cache' 'FIXED' 'cleared'
  }
}

if (-not $Audit) {
  try {
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    Add-R 'Explorer restart' 'FIXED' 'restarted'
  } catch {
    Add-R 'Explorer restart' 'NEED' $_.Exception.Message
  }
}

$results | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
L "CSV $csv"
L '==== Minimal-Taskbar finished ===='
Write-Host "Minimal-Taskbar done. Log: $log"
$need = @($results | Where-Object { $_.Status -eq 'NEED' }).Count
if ($need -gt 0 -and $Apply) { exit 2 } else { exit 0 }
