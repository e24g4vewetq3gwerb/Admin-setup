# Clear apps and system tray

One PowerShell script. Uninstall removable apps. Strip the taskbar down to **Start** and **Windows PowerShell**. Does not restart Explorer or the PC.

Repo: [e24g4vewetq3gwerb/Admin-setup](https://github.com/e24g4vewetq3gwerb/Admin-setup)

## What it does

1. Elevates with UAC if needed
2. Uninstalls removable Win32 apps (drivers, runtimes, Edge/WebView2 kept)
3. Removes removable Store packages (Store, App Installer, security / lock / system packages kept)
4. Hides search, widgets, Task View, Copilot, chat, clock, and the notification area
5. Pins Windows PowerShell next to Start; removes other taskbar pins
6. Exits. Never schedules a reboot. Never launches Explorer.

The Start button is part of the shell and stays. The PowerShell pin may not appear until the next sign-in.

## Run

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\admin" | Out-Null
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Clear-Apps-And-Tray.ps1 -OutFile "$env:USERPROFILE\admin\Clear-Apps-And-Tray.ps1"
Unblock-File "$env:USERPROFILE\admin\Clear-Apps-And-Tray.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\admin\Clear-Apps-And-Tray.ps1"
```

## Switches

| Switch | Effect |
|--------|--------|
| `-SkipWipe` | Only apply the taskbar / tray layout |
| `-SkipTray` | Only uninstall apps |

Log: `%USERPROFILE%\admin\Clear-Apps-And-Tray.log`
