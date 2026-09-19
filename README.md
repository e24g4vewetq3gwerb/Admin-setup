# Admin Setup

One script. Everything lives in `Admin-Setup.ps1`.

```powershell
$dst = "$env:USERPROFILE\admin\Admin-Setup.ps1"
New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Admin-Setup.ps1 -OutFile $dst
Unblock-File $dst
powershell -STA -NoProfile -ExecutionPolicy Bypass -File $dst
```

Modes:

| Mode | What it does |
|---|---|
| (default / All) | Remove removable Win32 + Store apps, clean caches, hide taskbar, badges, report |
| HideBar | Keep the taskbar hidden |
| Badges | Three logos. Trash = delete file, re-download, run default |
| WipeDisk | Clear Downloads/user folders and format other drives. Needs `-ConfirmPhrase WIPE-ALL-DATA` |
| CleanCaches | Temp, INetCache, Recycle Bin |
| Repair | **New.** Flush DNS, rebuild icon cache, restart Explorer, re-download script, restart badges |
| Uninstall | Stop helpers, restore taskbar, delete Admin Setup files |

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File $dst -Mode Repair
powershell -NoProfile -ExecutionPolicy Bypass -File $dst -Mode WipeDisk -ConfirmPhrase WIPE-ALL-DATA
powershell -NoProfile -ExecutionPolicy Bypass -File $dst -Mode Uninstall
```
