# Admin Setup

One Windows script. Wipe leftover apps, hide the tray, optional Grok Bot + Chrome, restart.

Repo: [e24g4vewetq3gwerb/Admin-setup](https://github.com/e24g4vewetq3gwerb/Admin-setup)

## What Admin-Setup.ps1 does

1. Copies itself to `%USERPROFILE%\admin\Admin-Setup.ps1`
2. Optional **Admin Setup** desktop / Start icon (Run as administrator)
3. Asks Yes/No for latest **Grok Bot** and **Google Chrome**
4. Wipes removable Win32 / Store apps (keeps drivers, Edge, Chrome, Grok Bot, App Installer)
5. Removes leftover Settings rows: **Snipping Tool** and **Windows Package Manager Source (winget) V2**
6. Clears the taskbar tray / extra buttons (`Set-MinimalTaskbar`)
7. Restarts (`-Restart` / `-RestartIfNeeded`)

`Microsoft.DesktopAppInstaller` is not removed (Windows returns `0x80070032`).

## Run

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\admin" | Out-Null
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Admin-Setup.ps1 -OutFile "$env:USERPROFILE\admin\Admin-Setup.ps1"
Unblock-File "$env:USERPROFILE\admin\Admin-Setup.ps1"
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\admin\Admin-Setup.ps1" -Apply -UninstallNotKept -RestartIfNeeded
```

Icon only:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\admin\Admin-Setup.ps1" -IconOnly
```

Log: `%USERPROFILE%\admin\Admin-Setup.log`
