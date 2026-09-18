<#
.SYNOPSIS
  Minimal dock-style taskbar: Chrome, Cursor, Grok Bot; optional Windhawk up-arrow-only tray.

.DESCRIPTION
  - Hides Widgets/weather, Search, Task View, Chat/Copilot
  - Centers taskbar icons
  - Demotes overflow NotifyIconSettings (IsPromoted=0); keeps the chevron
  - Does NOT set NoTrayItemsDisplay (that would hide the chevron)
  - Keeps pin shortcuts for Chrome, Cursor, Grok Bot only
  - On -Apply -IncludeWindhawkTray (default on Apply): runs Restore-TrayArrowOnly.ps1
    so language / Wi-Fi / volume / battery / Show Desktop are hidden via Windhawk

  Classic HideSCA* policies do not hide Control Center icons on Windows 11 25H2;
  Windhawk mod taskbar-tray-system-icon-tweaks is required for that.

  -Audit                 Report only (default)
  -Apply                 Write registry + clean pins + restart Explorer
  -IncludeWindhawkTray   Also configure Windhawk up-arrow-only tray (default when -Apply)
  -SkipWindhawkTray      Skip Windhawk even on -Apply
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [switch]$Audit,
  [switch]$Apply,
  [switch]$IncludeWindhawkTray,
  [switch]$SkipWindhawkTray
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
if (-not $Audit -and -not $Apply) { $Audit = $true }
if ($Apply -and -not $SkipWindhawkTray) { $IncludeWindhawkTray = $true }
if ($SkipWindhawkTray) { $IncludeWindhawkTray = $false }

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
  L "[$Status] $Item - $Detail"
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

L "==== Minimal-Taskbar Audit=$Audit Apply=$Apply IncludeWindhawkTray=$IncludeWindhawkTray ===="

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

# Keep the chevron: clear NoTrayItemsDisplay if present
$noTray = Get-RegInt $pol 'NoTrayItemsDisplay'
if ($Audit) {
  $want = if ($null -eq $noTray -or $noTray -eq 0) { 'OK' } else { 'NEED' }
  Add-R 'NoTrayItemsDisplay (must be off to keep chevron)' $want "current=$noTray want=absent/0"
} elseif ($null -ne $noTray -and $noTray -ne 0) {
  Remove-ItemProperty -Path $pol -Name 'NoTrayItemsDisplay' -Force -ErrorAction SilentlyContinue
  Add-R 'NoTrayItemsDisplay' 'FIXED' 'removed so chevron stays'
}

# Clock hide (best-effort on Win11)
Set-RegDword $adv 'ShowSystrayDateTimeValueName' 0 'Clock / date in tray'

# Other app tray icons -> overflow (not promoted)
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

if (-not $Audit) {
  try {
    New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Name 'AllowNewsAndInterests' -PropertyType DWord -Value 0 -Force | Out-Null
    Add-R 'Dsh AllowNewsAndInterests' 'FIXED' '0'
  } catch {
    Add-R 'Dsh AllowNewsAndInterests' 'NEED' $_.Exception.Message
  }
}

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
  $wh = Test-Path 'C:\Program Files\Windhawk\Windhawk.exe'
  Add-R 'Windhawk installed' $(if ($wh) { 'OK' } else { 'NEED' }) $(if ($wh) { 'present' } else { 'install for up-arrow-only tray' })
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

if ($IncludeWindhawkTray -and -not $Audit) {
  $restore = Join-Path $here 'Restore-TrayArrowOnly.ps1'
  if (Test-Path $restore) {
    L 'START Restore-TrayArrowOnly'
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $restore
    ) -Wait -PassThru -NoNewWindow
    Add-R 'Windhawk up-arrow tray' $(if ($p.ExitCode -eq 0) { 'FIXED' } else { 'NEED' }) "exit=$($p.ExitCode)"
  } else {
    Add-R 'Windhawk up-arrow tray' 'NEED' "missing $restore"
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
