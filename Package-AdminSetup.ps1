<#
.SYNOPSIS
  Package Admin-Setup.ps1 into Admin-Setup.exe with PS2EXE.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Package-AdminSetup.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Package-AdminSetup.ps1 -OutFile .\dist\Admin-Setup.exe
#>
[CmdletBinding()]
param(
  [string]$InputFile,
  [string]$OutFile
)
$ErrorActionPreference = 'Stop'
if (-not $InputFile) {
  $here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
  $InputFile = Join-Path $here 'Admin-Setup.ps1'
}
if (-not (Test-Path -LiteralPath $InputFile)) { throw "Admin-Setup.ps1 not found: $InputFile" }
& $InputFile -Package -OutFile $OutFile
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
