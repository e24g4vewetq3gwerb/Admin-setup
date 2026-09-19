<#
.SYNOPSIS
  Clear all drives except Windows system files. Live only with -ConfirmPhrase WIPE-ALL-DATA.
#>
[CmdletBinding()]
param(
  [switch]$Preview,
  [string]$ConfirmPhrase = ''
)
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::Title = 'Wipe-All-Except-Windows' } catch {}

function Test-IsAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-SelfPath {
  foreach ($c in @($PSCommandPath, $MyInvocation.MyCommand.Path, $MyInvocation.MyCommand.Definition)) {
    if ($c -and "$c" -like '*.ps1' -and (Test-Path -LiteralPath $c)) { return $c }
  }
  return $null
}

$live = ($ConfirmPhrase -eq 'WIPE-ALL-DATA')
if (-not $live) { $Preview = $true }

if (-not (Test-IsAdmin)) {
  $self = Get-SelfPath
  if (-not $self) { throw 'Save as .ps1 first.' }
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
  try { Add-Content -LiteralPath $log -Value $line } catch {}
  Write-Host $line
}

function Test-IsOsKeep([string]$Path) {
  try { $full = [IO.Path]::GetFullPath($Path) } catch { return $false }
  $leaf = ([IO.Path]::GetFileName($full)).ToLowerInvariant()
  $keepLeaf = @('windows','boot','bootmgr','bootnxt','bootsect.bak','recovery','$winreagent','system volume information','pagefile.sys','hiberfil.sys','swapfile.sys')
  if ($keepLeaf -contains $leaf) { return $true }
  $win = [IO.Path]::GetFullPath($winDir)
  if ($full -eq $win -or $full.StartsWith($win.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
  $ad = [IO.Path]::GetFullPath($adminDir)
  if ($full -eq $ad -or $full.StartsWith($ad.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
  return $false
}

function Remove-Force([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $true }
  if (Test-IsOsKeep $Path) { Write-Step "KEEP $Path"; return $true }
  if (-not $live) { Write-Step "WOULD DELETE $Path"; return $true }
  Write-Step "DELETE $Path"
  cmd.exe /c "attrib -s -h -r `"$Path`" /s /d >nul 2>&1" | Out-Null
  cmd.exe /c "takeown /F `"$Path`" /R /D Y >nul 2>&1" | Out-Null
  cmd.exe /c "icacls `"$Path`" /grant *S-1-5-32-544:F /T /C /Q >nul 2>&1" | Out-Null
  try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue } catch {}
  if (Test-Path -LiteralPath $Path -PathType Container) {
    $empty = Join-Path $env:TEMP ('wipe-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $empty | Out-Null
    cmd.exe /c "robocopy `"$empty`" `"$Path`" /MIR /R:0 /W:0 /NFL /NDL /NJH /NJS /NC /NS >nul" | Out-Null
    cmd.exe /c "rd /s /q `"$Path`"" | Out-Null
    try { Remove-Item -LiteralPath $empty -Force -ErrorAction SilentlyContinue } catch {}
  } else {
    cmd.exe /c "del /f /q `"$Path`"" | Out-Null
  }
  $gone = -not (Test-Path -LiteralPath $Path)
  Write-Step ($(if ($gone) { "GONE $Path" } else { "STILL THERE $Path" }))
  return $gone
}

Write-Step "Start live=$live preview=$Preview OS=$osRoot user=$env:USERPROFILE"

$roots = New-Object System.Collections.Generic.List[string]
Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -in 2, 3 } | ForEach-Object {
  $r = $_.DeviceID.TrimEnd('\') + '\'
  Write-Step ("DISK {0} type={1}" -f $_.DeviceID, $_.DriveType)
  if (Test-Path -LiteralPath $r) { [void]$roots.Add($r) }
}
Get-PSDrive -PSProvider FileSystem | ForEach-Object {
  $r = $_.Root
  if ($r -and (Test-Path -LiteralPath $r) -and -not ($roots -contains $r)) { [void]$roots.Add($r) }
}
Write-Step ("ROOTS {0}" -f ($roots -join ', '))

foreach ($root in $roots) {
  $letter = $root.TrimEnd('\')
  Write-Step "SCAN $letter"
  if ($letter -ne $osRoot) {
    Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | ForEach-Object {
      [void](Remove-Force $_.FullName)
    }
    continue
  }
  Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $name = $_.Name.ToLowerInvariant()
    if ($name -eq 'users') { return }
    [void](Remove-Force $_.FullName)
  }
}

$usersRoot = Join-Path $osRoot 'Users'
if (Test-Path -LiteralPath $usersRoot) {
  $dataDirs = @('Downloads','Documents','Desktop','Pictures','Videos','Music','OneDrive','3D Objects','Favorites','Links','Saved Games','Searches','Contacts')
  Get-ChildItem -LiteralPath $usersRoot -Force -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $profile = $_.FullName
    $short = $_.Name.ToLowerInvariant()
    if ($short -in @('public','default','default user','all users')) {
      foreach ($d in $dataDirs) {
        $p = Join-Path $profile $d
        if (Test-Path -LiteralPath $p) { [void](Remove-Force $p) }
      }
      return
    }
    if ($profile -eq $env:USERPROFILE) {
      foreach ($d in $dataDirs) {
        $p = Join-Path $profile $d
        if (Test-Path -LiteralPath $p) { [void](Remove-Force $p) }
      }
      return
    }
    [void](Remove-Force $profile)
  }
}

Write-Step 'Done'
Write-Host "Log $log"
try { Start-Process notepad.exe $log | Out-Null } catch {}
if ($live) { Start-Sleep -Seconds 8 }
