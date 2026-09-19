# Merged into Admin-Setup.ps1
# This file stays as a thin alias: leftover Settings rows + tray hide + no extra prompts.
# Prefer: Admin-Setup.ps1 -Apply -UninstallNotKept -RestartIfNeeded
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$main = Join-Path $here 'Admin-Setup.ps1'
if (-not (Test-Path -LiteralPath $main)) {
  $main = Join-Path $env:USERPROFILE 'admin\Admin-Setup.ps1'
}
if (-not (Test-Path -LiteralPath $main)) {
  New-Item -ItemType Directory -Force -Path (Join-Path $env:USERPROFILE 'admin') | Out-Null
  Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Admin-Setup.ps1' -OutFile $main -UseBasicParsing
}
powershell -NoProfile -ExecutionPolicy Bypass -File $main -Apply -UninstallNotKept -SkipOffer -RestartIfNeeded
