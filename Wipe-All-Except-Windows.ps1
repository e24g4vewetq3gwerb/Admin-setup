<#
.SYNOPSIS
  Preview or delete everything on all drives except Windows system files.
  Default is -WhatIf (no delete). Live run requires -ConfirmPhrase WIPE-ALL-DATA.
  Not wired to the trash badge.
#>
[CmdletBinding()]
param(
  [switch]$WhatIf,
  [string]$ConfirmPhrase = '',
  [string[]]$AlsoKeep = @()
)
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

if (-not $PSBoundParameters.ContainsKey('WhatIf')) { $WhatIf = $true }

function Test-IsAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-SelfPath {
  foreach ($c in @($PSCommandPath, $MyInvocation.MyCommand.Path)) {
    if ($c -and (Test-Path -LiteralPath $c)) { return $c }
  }
  return $null
}

if (-not (Test-IsAdmin)) {
  $self = Get-SelfPath
  if (-not $self) { throw 'Run elevated.' }
  $arg = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$self`"")
  if ($WhatIf) { $arg += '-WhatIf' }
  if ($ConfirmPhrase) { $arg += @('-ConfirmPhrase', $ConfirmPhrase) }
  Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList $arg | Out-Null
  return
}

$osRoot = $env:SystemDrive.TrimEnd('\')
$winDir = $env:SystemRoot
$adminDir = Join-Path $env:USERPROFILE 'admin'
$keepExact = New-Object System.Collections.Generic.List[string]
foreach ($k in @(
    $winDir,
    (Join-Path $osRoot 'Boot'),
    (Join-Path $osRoot 'bootmgr'),
    (Join-Path $osRoot 'BOOTNXT'),
    (Join-Path $osRoot 'BOOTSECT.BAK'),
    (Join-Path $osRoot 'Recovery'),
    (Join-Path $osRoot '$WinREAgent'),
    (Join-Path $osRoot 'System Volume Information'),
    (Join-Path $osRoot 'pagefile.sys'),
    (Join-Path $osRoot 'hiberfil.sys'),
    (Join-Path $osRoot 'swapfile.sys'),
    $adminDir
  ) + @($AlsoKeep)) {
  if ($k) { [void]$keepExact.Add($k) }
}

function Test-IsKept([string]$Path) {
  try { $full = [IO.Path]::GetFullPath($Path) } catch { return $false }
  foreach ($k in $keepExact) {
    try { $kk = [IO.Path]::GetFullPath($k) } catch { continue }
    if ($full -eq $kk) { return $true }
    $prefix = $kk.TrimEnd('\') + '\'
    if ($full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
  }
  return $false
}

$live = (-not $WhatIf) -and ($ConfirmPhrase -eq 'WIPE-ALL-DATA')
New-Item -ItemType Directory -Force -Path $adminDir | Out-Null
$log = Join-Path $adminDir 'Wipe-All-Except-Windows.log'
function Write-Step([string]$m) {
  $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $m
  try { Add-Content -Path $log -Value $line } catch {}
  Write-Host $line
}
Write-Step "Start WhatIf=$WhatIf Live=$live OS=$osRoot"

if (-not $WhatIf -and -not $live) {
  Write-Step 'Refusing live delete. Use -WhatIf:$false -ConfirmPhrase WIPE-ALL-DATA'
  return
}

function Remove-Target([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return }
  if (Test-IsKept $Path) { Write-Step "KEEP $Path"; return }
  if (-not $live) { Write-Step "WOULD DELETE $Path"; return }
  Write-Step "DELETE $Path"
  try { cmd /c "takeown /F `"$Path`" /R /D Y" | Out-Null } catch {}
  try { cmd /c "icacls `"$Path`" /grant Administrators:F /T /C" | Out-Null } catch {}
  try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue } catch {
    Write-Step "FAIL $Path $($_.Exception.Message)"
  }
}

Get-PSDrive -PSProvider FileSystem | ForEach-Object {
  $root = $_.Root.TrimEnd('\')
  if ($root -eq $osRoot) { return }
  Write-Step "DRIVE $root"
  Get-ChildItem -LiteralPath ($root + '\') -Force -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Target $_.FullName
  }
}

Write-Step "DRIVE $osRoot"
Get-ChildItem -LiteralPath ($osRoot + '\') -Force -ErrorAction SilentlyContinue | ForEach-Object {
  Remove-Target $_.FullName
}

Write-Step 'Done'
Write-Host "Log: $log"
