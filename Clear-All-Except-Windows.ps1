<#
.SYNOPSIS
  Delete every folder on every drive except Windows OS folders needed to boot.
  Live: -ConfirmPhrase WIPE-ALL-DATA
#>
[CmdletBinding()]
param([string]$ConfirmPhrase = '')
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'
$live = ($ConfirmPhrase -eq 'WIPE-ALL-DATA')
function Test-IsAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-IsAdmin)) {
  $self = $PSCommandPath
  if (-not $self) { throw 'Save as .ps1 first' }
  $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$self`""
  if ($live) { $arg += ' -ConfirmPhrase WIPE-ALL-DATA' }
  Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList $arg
  return
}
$admin = Join-Path $env:USERPROFILE 'admin'
New-Item -ItemType Directory -Force -Path $admin | Out-Null
$log = Join-Path $admin 'Clear-All-Except-Windows.log'
function L([string]$m) { $t = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $m; Add-Content $log $t; Write-Host $t }
L "live=$live OS=$env:SystemDrive"
$keepLeaf = @('windows','boot','bootmgr','bootnxt','bootsect.bak','recovery','$winreagent','system volume information','pagefile.sys','hiberfil.sys','swapfile.sys')
function IsKeep([string]$p) {
  try { $f = [IO.Path]::GetFullPath($p) } catch { return $false }
  $leaf = ([IO.Path]::GetFileName($f)).ToLowerInvariant()
  if ($keepLeaf -contains $leaf) { return $true }
  $win = [IO.Path]::GetFullPath($env:SystemRoot)
  if ($f -eq $win -or $f.StartsWith($win.TrimEnd('\')+'\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
  $ad = [IO.Path]::GetFullPath($admin)
  if ($f -eq $ad -or $f.StartsWith($ad.TrimEnd('\')+'\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
  return $false
}
function KillPath([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { return }
  if (IsKeep $p) { L "KEEP $p"; return }
  L "CLEAR $p"
  if (-not $live) { return }
  cmd /c "attrib -s -h -r `"$p`" /s /d >nul 2>&1"
  cmd /c "takeown /F `"$p`" /R /D Y >nul 2>&1"
  cmd /c "icacls `"$p`" /grant Administrators:F /T /C /Q >nul 2>&1"
  try { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue } catch {}
  if (Test-Path -LiteralPath $p -PathType Container) {
    $e = Join-Path $env:TEMP ('c'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $e | Out-Null
    cmd /c "robocopy `"$e`" `"$p`" /MIR /R:0 /W:0 /NFL /NDL /NJH /NJS >nul"
    cmd /c "rd /s /q `"$p`""
    Remove-Item $e -Force -ErrorAction SilentlyContinue
  }
  if (Test-Path -LiteralPath $p) { L "LEFT $p" } else { L "GONE $p" }
}
# Known folders including OneDrive Downloads
$shell = New-Object -ComObject Shell.Application
foreach ($id in 5,0x10,0x13,0x27,13,14,39) {
  try { $n = $shell.NameSpace($id); if ($n -and $n.Self.Path) { KillPath $n.Self.Path } } catch {}
}
foreach ($name in @('Downloads','Documents','Desktop','Pictures','Videos','Music','OneDrive')) {
  KillPath (Join-Path $env:USERPROFILE $name)
}
$os = $env:SystemDrive.TrimEnd(':')
Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -in 2,3 } | ForEach-Object {
  $letter = $_.DeviceID.TrimEnd(':')
  L "DRIVE $($_.DeviceID) type=$($_.DriveType)"
  if ($letter -ne $os) {
    if ($live) {
      try { Format-Volume -DriveLetter $letter -FileSystem NTFS -NewFileSystemLabel 'DATA' -Force -Confirm:$false -ErrorAction Stop | Out-Null; L "FORMATTED $letter"; return } catch { L "FORMAT FAIL $letter $($_.Exception.Message)" }
    }
  }
  $root = $letter + ':\'
  Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -eq 'Users' -and $letter -eq $os) {
      Get-ChildItem $_.FullName -Force -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        foreach ($n in @('Downloads','Documents','Desktop','Pictures','Videos','Music','OneDrive','3D Objects')) {
          KillPath (Join-Path $_.FullName $n)
        }
      }
    } else {
      KillPath $_.FullName
    }
  }
}
L 'DONE'
Start-Process notepad.exe $log
