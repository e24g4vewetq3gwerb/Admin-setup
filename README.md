# Admin Setup

One script.

```powershell
$dst = "$env:USERPROFILE\admin\Admin-Setup.ps1"
New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Admin-Setup.ps1 -OutFile $dst
Unblock-File $dst
powershell -STA -NoProfile -ExecutionPolicy Bypass -File $dst
```

Modes:

- (default) wipe removable apps, hide taskbar, badges, report, clean caches
- `-Mode HideBar`
- `-Mode Badges`
- `-Mode WipeDisk -ConfirmPhrase WIPE-ALL-DATA`
- `-Mode Uninstall`
- `-Mode CleanCaches`

Trash badge = delete this file, download it again, run default mode.
