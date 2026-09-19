<#
.SYNOPSIS
  On every drive except the Windows folder: select all files and folders and delete them.
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
  Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -Wait -ArgumentList $arg
  return
}
$admin = Join-Path $env:USERPROFILE 'admin'
New-Item -ItemType Directory -Force -Path $admin | Out-Null
$log = Join-Path $admin 'Clear-All-Except-Windows.log'
function L([string]$m) { $t = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $m; Add-Content -LiteralPath $log -Value $t; Write-Host $t }
L "live=$live OS=$env:SystemDrive"
function Delete-AllInside([string]$Root) {
  if (-not (Test-Path -LiteralPath $Root)) { L "MISSING $Root"; return }
  L "SELECT ALL IN $Root"
  $items = @(Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue)
  L ("COUNT {0} items" -f $items.Count)
  foreach ($item in $items) {
    $p = $item.FullName
    L "DELETE $p"
    if (-not $live) { continue }
    cmd /c "attrib -s -h -r `"$p`" /s /d >nul 2>&1"
    cmd /c "takeown /F `"$p`" /R /D Y >nul 2>&1"
    cmd /c "icacls `"$p`" /grant Administrators:F /T /C /Q >nul 2>&1"
    try { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    if (Test-Path -LiteralPath $p -PathType Container) {
      $empty = Join-Path $env:TEMP ('wipe-' + [guid]::NewGuid().ToString('N'))
      New-Item -ItemType Directory -Force -Path $empty | Out-Null
      cmd /c "robocopy `"$empty`" `"$p`" /MIR /R:0 /W:0 /NFL /NDL /NJH /NJS >nul"
      cmd /c "rd /s /q `"$p`""
      Remove-Item -LiteralPath $empty -Force -ErrorAction SilentlyContinue
    } else {
      cmd /c "del /f /q `"$p`""
    }
    if (Test-Path -LiteralPath $p) { L "LEFT $p" } else { L "GONE $p" }
  }
}
$osRoot = $env:SystemDrive.TrimEnd('\') + '\'
$keepOnC = @('windows','boot','bootmgr','bootnxt','bootsect.bak','recovery','$winreagent','system volume information','pagefile.sys','hiberfil.sys','swapfile.sys')
# C: delete every top-level item except Windows OS files; inside Users delete data folders including Downloads
L "C DRIVE $osRoot"
Get-ChildItem -LiteralPath $osRoot -Force -ErrorAction SilentlyContinue | ForEach-Object {
  $leaf = $_.Name.ToLowerInvariant()
  if ($keepOnC -contains $leaf) { L "KEEP $($_.FullName)"; return }
  if ($leaf -eq 'users') {
    Get-ChildItem -LiteralPath $_.FullName -Force -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      foreach ($n in @('Downloads','Documents','Desktop','Pictures','Videos','Music','OneDrive','3D Objects','Favorites','Links','Saved Games','Searches','Contacts')) {
        $p = Join-Path $_.FullName $n
        if (Test-Path -LiteralPath $p) { Delete-AllInside $p }
      }
    }
    return
  }
  L "DELETE $($_.FullName)"
  if ($live) {
    $p = $_.FullName
    cmd /c "attrib -s -h -r `"$p`" /s /d >nul 2>&1"
    cmd /c "takeown /F `"$p`" /R /D Y >nul 2>&1"
    try { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    if (Test-Path -LiteralPath $p -PathType Container) {
      $empty = Join-Path $env:TEMP ('wipe-' + [guid]::NewGuid().ToString('N'))
      New-Item -ItemType Directory -Force -Path $empty | Out-Null
      cmd /c "robocopy `"$empty`" `"$p`" /MIR /R:0 /W:0 /NFL /NDL /NJH /NJS >nul"
      cmd /c "rd /s /q `"$p`""
      Remove-Item -LiteralPath $empty -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $p) { L "LEFT $p" } else { L "GONE $p" }
  }
}
# Other drives: select all files and folders, delete
Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -in 2,3,6 } | ForEach-Object {
  $letter = $_.DeviceID.TrimEnd(':')
  $root = $letter + ':\'
  if ($root -eq $osRoot) { return }
  L "OTHER DRIVE $root type=$($_.DriveType)"
  Delete-AllInside $root
}
Get-PSDrive -PSProvider FileSystem | ForEach-Object {
  if ($_.Name.Length -ne 1) { return }
  $root = $_.Root
  if ($root -eq $osRoot) { return }
  if (-not (Test-Path -LiteralPath $root)) { return }
  L "PSDRIVE $root"
  Delete-AllInside $root
}
L 'DONE'
Start-Process notepad.exe $log
