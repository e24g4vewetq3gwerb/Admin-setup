<#
.SYNOPSIS
  Compatibility wrapper — use Offer-GrokAndChrome.ps1.

.DESCRIPTION
  Forwards to Offer-GrokAndChrome.ps1 (Grok Bot + Google Chrome offer / install / pin).
#>
[CmdletBinding()]
param(
  [switch]$RegisterRunOnce,
  [switch]$ForceAsk
)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$target = Join-Path $here 'Offer-GrokAndChrome.ps1'
if (-not (Test-Path $target)) { throw "Missing $target" }
$args = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $target)
if ($RegisterRunOnce) { $args += '-RegisterRunOnce' }
if ($ForceAsk) { $args += '-ForceAsk' }
$p = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Wait -PassThru -NoNewWindow
exit $p.ExitCode
