<#
.SYNOPSIS
  Wrapper: same as Admin-Setup.ps1 so the old trash badge path still works.
#>
[CmdletBinding()]
param(
  [ValidateSet('All','Wipe','HideBar','Badges')]
  [string]$Mode = 'All',
  [switch]$SkipWipe,
  [switch]$SkipTray,
  [switch]$ShowReport
)
$here = Split-Path -Parent $PSCommandPath
$main = Join-Path $here 'Admin-Setup.ps1'
if (-not (Test-Path -LiteralPath $main)) {
  $main = Join-Path $env:USERPROFILE 'admin\Admin-Setup.ps1'
}
if (Test-Path -LiteralPath $main) {
  $arg = @('-STA','-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$main`"",'-Mode',$Mode)
  if ($SkipWipe) { $arg += '-SkipWipe' }
  if ($SkipTray) { $arg += '-SkipTray' }
  if ($ShowReport) { $arg += '-ShowReport' }
  & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @arg
  return
}
Write-Host 'Admin-Setup.ps1 not found. Download it to %USERPROFILE%\admin\Admin-Setup.ps1'
