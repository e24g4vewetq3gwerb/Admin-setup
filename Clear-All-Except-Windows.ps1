<#
.SYNOPSIS
  Empty Downloads and all non-Windows folders. Format every drive that is not C:.
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
Get-CimInstance Win32_LogicalDisk | ForEach-Object { L ("DISK {0} type={1} fs={2}" -f $_.DeviceID, $_.DriveType, $_.FileSystem) }
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
  if (-not $p -or -not (Test-Path -LiteralPath $p)) { return }
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
function Clear-OtherDrive([string]$Letter) {
  $root = $Letter + ':\'
  L "OTHER DRIVE $root"
  if (-not (Test-Path -LiteralPath $root)) { L "MISSING $root"; return }
  if (-not $live) { Get-ChildItem $root -Force -ErrorAction SilentlyContinue | ForEach-Object { L "WOULD $($_.FullName)" }; return }
  $formatted = $false
  try {
    Format-Volume -DriveLetter $Letter -FileSystem NTFS -NewFileSystemLabel 'DATA' -Force -Confirm:$false -ErrorAction Stop | Out-Null
    $formatted = $true
    L "FORMATTED $Letter"
  } catch { L "FORMAT FAIL $Letter $($_.Exception.Message)" }
  if (-not $formatted) {
    Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | ForEach-Object { KillPath $_.FullName }
    $script = "select volume $Letter`r`nformat fs=ntfs label=DATA quick override`r`n"
    $tmp = Join-Path $env:TEMP 'fmt-other.txt'
    Set-Content -Path $tmp -Value $script -Encoding ASCII
    cmd /c "diskpart /s `"$tmp`"" | ForEach-Object { L "diskpart $_" }
  }
}
$shell = New-Object -ComObject Shell.Application
foreach ($id in 5,0x10,0x13,0x27,13,14,39) {
  try { $n = $shell.NameSpace($id); if ($n -and $n.Self.Path) { KillPath $n.Self.Path } } catch {}
}
foreach ($name in @('Downloads','Documents','Desktop','Pictures','Videos','Music','OneDrive')) {
  KillPath (Join-Path $env:USERPROFILE $name)
}
$os = $env:SystemDrive.TrimEnd(':').TrimEnd('\')
$seen = @{}
Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -in 2,3,6 } | ForEach-Object {
  $letter = $_.DeviceID.TrimEnd(':').TrimEnd('\')
  if (-not $letter) { return }
  $seen[$letter] = $true
  if ($letter -eq $os) {
    L "OS DRIVE $($_.DeviceID)"
    Get-ChildItem -LiteralPath ($letter+':\') -Force -ErrorAction SilentlyContinue | ForEach-Object {
      if ($_.Name -eq 'Users') {
        Get-ChildItem $_.FullName -Force -Directory -ErrorAction SilentlyContinue | ForEach-Object {
          foreach ($n in @('Downloads','Documents','Desktop','Pictures','Videos','Music','OneDrive','3D Objects')) {
            KillPath (Join-Path $_.FullName $n)
          }
        }
      } else { KillPath $_.FullName }
    }
  } else {
    Clear-OtherDrive $letter
  }
}
Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | ForEach-Object {
  $letter = $_.Name
  if ($letter.Length -ne 1) { return }
  if ($seen.ContainsKey($letter)) { return }
  if ($letter -eq $os) { return }
  L "EXTRA PSDrive $letter"
  Clear-OtherDrive $letter
}
L 'DONE'
try { Start-Process notepad.exe $log } catch {}
