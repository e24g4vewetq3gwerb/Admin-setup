# Admin Setup

**Version:** `20260919` restore — report window is back.

One script: `Clear-Apps-And-Tray.ps1`

Removes removable programs, hides the taskbar, shows three badges (folder / PowerShell / trash). Opens the dark **what ran** window when finished.

## Run

```powershell
$dst = "$env:USERPROFILE\admin\Clear-Apps-And-Tray.ps1"
New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Clear-Apps-And-Tray.ps1 -OutFile $dst
Unblock-File $dst
powershell -STA -NoProfile -ExecutionPolicy Bypass -File $dst
```

Approve UAC. The report window title is **Admin Setup - what ran**.
