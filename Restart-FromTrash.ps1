<#
  Same steps as typing the setup command by hand.
  Download Admin-Setup.ps1 and run default mode (apps, caches, taskbar, badges, report).
#>
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$dst = Join-Path $env:USERPROFILE 'admin\Admin-Setup.ps1'
New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Admin-Setup.ps1' -OutFile $dst
Unblock-File $dst
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -STA -NoProfile -ExecutionPolicy Bypass -File $dst
