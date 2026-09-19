# Admin Setup

One Windows script. One README. Optional desktop icon. Optional packaged `.exe`.

Repo: [e24g4vewetq3gwerb/Admin-setup](https://github.com/e24g4vewetq3gwerb/Admin-setup)

## What it does

1. Copies itself to `%USERPROFILE%\admin\Admin-Setup.ps1` (or `Admin-Setup.exe` if you ran the packaged build)
2. Asks whether to put **Admin Setup** on the Desktop and Start (Run as administrator)
3. Asks **Yes / No** for latest **Grok Bot** and **Google Chrome**
4. On **Yes**, downloads and installs **now** (still elevated — not after reboot)
5. Optional wipe of removable apps (drivers / runtimes / Chrome / Grok Bot kept)
6. Restarts only after that work is done (`-Restart` / `-RestartIfNeeded`)

## Package a .exe

Windows only. Uses [PS2EXE](https://www.powershellgallery.com/packages/ps2exe) and marks the build `requireAdmin` so double-click prompts UAC.

```powershell
powershell -ExecutionPolicy Bypass -File .\Admin-Setup.ps1 -Package
```

Or:

```powershell
powershell -ExecutionPolicy Bypass -File .\Package-AdminSetup.ps1
```

Custom output path:

```powershell
powershell -ExecutionPolicy Bypass -File .\Admin-Setup.ps1 -Package -OutFile .\dist\Admin-Setup.exe
```

Default output: `Admin-Setup.exe` next to the script. The packaged exe:

- Reloads itself into `%USERPROFILE%\admin\Admin-Setup.exe`
- Points the desktop shortcut at that exe
- Relaunches itself elevated (no `powershell.exe -File`)

GitHub Actions on `windows-latest` also builds the exe and uploads it as the **Admin-Setup-exe** workflow artifact whenever `Admin-Setup.ps1` changes.

## Desktop icon option

On a normal run the first box is: **add the Admin Setup icon?**

| Switch | Effect |
|--------|--------|
| *(none)* | Ask Yes/No for the icon |
| `-DesktopIcon` | Create the icon, no ask |
| `-SkipDesktopIcon` | Do not create the icon |
| `-IconOnly` | Create the icon and exit |

The shortcut is `Admin Setup.lnk` on the Desktop and in Start. It runs this same script (or the packaged exe) elevated.

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

Packaged exe (same switches):

```text
Admin-Setup.exe -Apply -UninstallNotKept -RestartIfNeeded
```

Cancel a pending reboot: `shutdown /a`

Log: `%USERPROFILE%\admin\Admin-Setup.log`

## One-liner (download from GitHub)

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\admin" | Out-Null
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Admin-Setup.ps1 -OutFile "$env:USERPROFILE\admin\Admin-Setup.ps1"
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\admin\Admin-Setup.ps1" -Apply -UninstallNotKept -RestartIfNeeded
```
