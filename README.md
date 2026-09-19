# Clear apps and system tray

One PowerShell script. Uninstall removable apps. Empty the notification area. Does not restart unless you pass `-Restart`.

Repo: [e24g4vewetq3gwerb/Admin-setup](https://github.com/e24g4vewetq3gwerb/Admin-setup)

This replaces the old Admin Setup flow (no Grok Bot / Chrome offer, no desktop icon installer).

## What it does

1. Elevates with UAC if needed
2. Uninstalls removable Win32 apps (drivers, runtimes, Edge/WebView2 kept)
3. Removes removable Store packages (Store, App Installer, security / lock / system packages kept)
4. Hides the system tray and extra taskbar buttons
5. Does **not** restart by default. Pass `-Restart` to schedule `shutdown /r /t 20`.

Chrome, Grok Bot, Office, games, and other third-party apps are not kept.

## Run

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\admin" | Out-Null
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Clear-Apps-And-Tray.ps1 -OutFile "$env:USERPROFILE\admin\Clear-Apps-And-Tray.ps1"
Unblock-File "$env:USERPROFILE\admin\Clear-Apps-And-Tray.ps1"
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\admin\Clear-Apps-And-Tray.ps1"
```

From a clone:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Clear-Apps-And-Tray.ps1
```

## Switches

| Switch | Effect |
|--------|--------|
| `-Restart` | Schedule reboot after the script finishes |
| `-NoRestart` | Same as default (no reboot). Kept so existing commands still work |
| `-SkipWipe` | Only clear the tray |
| `-SkipTray` | Only uninstall apps |
| `-RestartDelaySeconds 20` | Seconds before reboot when `-Restart` is set (default 20) |

Cancel a pending reboot: `shutdown /a`

Log: `%USERPROFILE%\admin\Clear-Apps-And-Tray.log`
