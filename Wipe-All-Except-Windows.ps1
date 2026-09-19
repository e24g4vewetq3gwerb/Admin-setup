<#
.SYNOPSIS
  Delete everything on all fixed drives except Windows system files.
  Live run: -ConfirmPhrase WIPE-ALL-DATA
  Preview:  -Preview
#>
[CmdletBinding()]
param(
  [switch]$Preview,
  [string]$ConfirmPhrase = ''
)
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

function Test-IsAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-SelfPath {
  foreach ($c in @($PSCommandPath, $MyInvocation.MyCommand.Path, $MyInvocation.MyCommand.Definition)) {
    if ($c -and $c -like '*.ps1' -and (Test-Path -LiteralPath $c)) { return $c }
  }
  return $null
}

$live = ($ConfirmPhrase -eq 'WIPE-ALL-DATA')
if (-not $live) { $Preview = $true }

if (-not (Test-IsAdmin)) {
  $self = Get-SelfPath
  if (-not $self) { throw 'Save as a .ps1 and run elevated.' }
  $arg = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$self`"")
  if ($live) { $arg += @('-ConfirmPhrase','WIPE-ALL-DATA') } else { $arg += '-Preview' }
  Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -Wait -ArgumentList $arg | Out-Null
  return
}

$osRoot = $env:SystemDrive.TrimEnd('\')
$winDir = $env:SystemRoot
$adminDir = Join-Path $env:USERPROFILE 'admin'
New-Item -ItemType Directory -Force -Path $adminDir | Out-Null
$log = Join-Path $adminDir 'Wipe-All-Except-Windows.log'
function Write-Step([string]$m) {
  $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $m
  try { Add-Content -Path $log -Value $line } catch {}
  Write-Host $line
}

$keepNames = @(
  'windows',
  'boot',
  'bootmgr',
  'bootnxt',
  'bootsect.bak',
  'recovery',
  '$winreagent',
  'system volume information',
  'pagefile.sys',
  'hiberfil.sys',
  'swapfile.sys',
  '$recycle.bin',
  'documents and settings'
)
function Test-IsKept([string]$Path) {
  try { $full = [IO.Path]::GetFullPath($Path) } catch { return $false }
  $leaf = [IO.Path]::GetFileName($full)
  if ($keepNames -contains $leaf.ToLowerInvariant()) { return $true }
  $win = [IO.Path]::GetFullPath($winDir)
  if ($full -eq $win -or $full.StartsWith($win.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
  $ad = [IO.Path]::GetFullPath($adminDir)
  if ($full -eq $ad -or $full.StartsWith($ad.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
  return $false
}

function Clear-Tree([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return }
  if (Test-IsKept $Path) { Write-Step "KEEP $Path"; return }
  if ($Preview -or -not $live) { Write-Step "WOULD DELETE $Path"; return }
  Write-Step "DELETE $Path"
  try { cmd.exe /c "takeown /F `"$Path`" /R /D Y >nul 2>&1" } catch {}
  try { cmd.exe /c "icacls `"$Path`" /grant Administrators:F /T /C /Q >nul 2>&1" } catch {}
  try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue } catch {}
  if (Test-Path -LiteralPath $Path) {
    $empty = Join-Path $env:TEMP ('wipeempty-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $empty | Out-Null
    if (Test-Path -LiteralPath $Path -PathType Container) {
      try { cmd.exe /c "robocopy `"$empty`" `"$Path`" /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NC /NS >nul" } catch {}
      try { cmd.exe /c "rd /s /q `"$Path`"" } catch {}
    } else {
      try { cmd.exe /c "del /f /q `"$Path`"" } catch {}
    }
    try { Remove-Item -LiteralPath $empty -Force -ErrorAction SilentlyContinue } catch {}
  }
  if (Test-Path -LiteralPath $Path) { Write-Step "STILL THERE $Path" } else { Write-Step "GONE $Path" }
}

Write-Step "Start live=$live preview=$Preview OS=$osRoot user=$env:USERNAME"
Write-Host 'Drives:'
Get-CimInstance Win32_LogicalDisk | ForEach-Object {
  Write-Step ("DISK {0} type={1} size={2}" -f $_.DeviceID, $_.DriveType, $_.Size)
}

# 2 = removable, 3 = local, 4 = network skip
$disks = @(Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -in 2, 3 })
if ($disks.Count -eq 0) { $disks = Get-PSDrive -PSProvider FileSystem }

foreach ($d in $disks) {
  $root = if ($d.DeviceID) { ($d.DeviceID.TrimEnd('\') + '\') } else { $d.Root }
  if (-not (Test-Path -LiteralPath $root)) { Write-Step "SKIP missing $root"; continue }
  Write-Step "SCAN $root"
  Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | ForEach-Object {
    Clear-Tree $_.FullName
  }
}

# Explicit user junk even if something kept Users
foreach ($p in @(
    (Join-Path $env:USERPROFILE 'Downloads'),
    (Join-Path $env:USERPROFILE 'Documents'),
    (Join-Path $env:USERPROFILE 'Desktop'),
    (Join-Path $env:USERPROFILE 'Pictures'),
    (Join-Path $env:USERPROFILE 'Videos'),
    (Join-Path $env:USERPROFILE 'Music'),
    (Join-Path $env:USERPROFILE 'OneDrive')
  )) {
  if (Test-Path -LiteralPath $p) { Clear-Tree $p }
}

Write-Step 'Done'
Write-Host "Log $log"
Start-Process notepad.exe $log | Out-Null
