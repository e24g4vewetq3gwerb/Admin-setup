# Admin Setup

One Windows script. One README. Optional desktop icon.

Repo: [e24g4vewetq3gwerb/Admin-setup](https://github.com/e24g4vewetq3gwerb/Admin-setup)

## What it does

1. Copies itself to `%USERPROFILE%\admin\Admin-Setup.ps1`
2. Asks whether to put **Admin Setup** on the Desktop and Start (Run as administrator)
3. Asks **Yes / No** for latest **Grok Bot** and **Google Chrome**
4. On **Yes**, downloads and installs **now** (still elevated — not after reboot)
5. Optional wipe of removable apps (drivers / runtimes / Chrome / Grok Bot kept)
6. Restarts only after that work is done (`-Restart` / `-RestartIfNeeded`)

## Desktop icon option

On a normal run the first box is: **add the Admin Setup icon?**

| Switch | Effect |
|--------|--------|
| *(none)* | Ask Yes/No for the icon |
| `-DesktopIcon` | Create the icon, no ask |
| `-SkipDesktopIcon` | Do not create the icon |
| `-IconOnly` | Create the icon and exit |

The shortcut is `Admin Setup.lnk` on the Desktop and in Start. It runs this same script elevated.

## Run

```powershell
powershell -ExecutionPolicy Bypass -File .\Admin-Setup.ps1 -Apply -UninstallNotKept -RestartIfNeeded
```

Force the icon:

```powershell
powershell -ExecutionPolicy Bypass -File .\Admin-Setup.ps1 -DesktopIcon -Apply -UninstallNotKept -RestartIfNeeded
```

Icon only:

```powershell
powershell -ExecutionPolicy Bypass -File .\Admin-Setup.ps1 -IconOnly
```

Offer apps, skip wipe:

```powershell
powershell -ExecutionPolicy Bypass -File .\Admin-Setup.ps1 -SkipWipe
```

Cancel a pending reboot: `shutdown /a`

Log: `%USERPROFILE%\admin\Admin-Setup.log`

## One-liner (download from GitHub)

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\admin" | Out-Null
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Admin-Setup.ps1 -OutFile "$env:USERPROFILE\admin\Admin-Setup.ps1"
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\admin\Admin-Setup.ps1" -Apply -UninstallNotKept -RestartIfNeeded
```
