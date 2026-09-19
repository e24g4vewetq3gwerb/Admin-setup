# Admin Setup

**Version:** `20260919` — one script, one README.

Uninstalls removable programs, hides the Windows taskbar, and shows three launch badges at the bottom of the screen.

Win key still opens Start. No reboot.

## How it looks

A transparent bar sits at the bottom center. Three circles:

| Badge | Look | Click |
| --- | --- | --- |
| Folder | dark + gold ring + Explorer icon | Opens your user profile folder |
| PowerShell | dark blue + blue ring + PowerShell icon | Opens PowerShell |
| Wipe | dark green + green ring + **trash can** | Asks **Confirm wipe?** (default No). Yes → UAC → wipe + report |

```
        [ folder ]     [ PowerShell ]     [ trash ]
                         bottom center
```

The real taskbar is hidden while the script’s hide loop is running.

## Run

```powershell
$dst = "$env:USERPROFILE\admin\Admin-Setup.ps1"
New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Admin-Setup.ps1 -OutFile $dst
Unblock-File $dst
powershell -STA -NoProfile -ExecutionPolicy Bypass -File $dst
```

Hide the taskbar and show badges **without** uninstalling apps:

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\admin\Admin-Setup.ps1" -SkipWipe
```

Reload badges only:

```powershell
powershell -STA -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$env:USERPROFILE\admin\Admin-Setup.ps1" -Mode Badges
```

## Modes

| Mode | What it does |
| --- | --- |
| `All` (default) | Wipe + hide taskbar + start badges |
| `Wipe` | Same as All when launched from the trash button |
| `HideBar` | Background loop that keeps `Shell_TrayWnd` hidden |
| `SkipWipe` | Hide taskbar + badges only |
| `Badges` | Three-circle bar only |

Logon Run keys point at this same file (`AdminSetupHideTaskbar`, `AdminSetupFolderLogo`).

## What the wipe keeps

Drivers, Visual C++, .NET, Edge / WebView2, Windows updates, Intel / NVIDIA / AMD, printer software, Windows Terminal / SDK, Store, and other system packages.

When it finishes, a dark report lists Found / Cleared / Kept / Failed.

## Stop

Task Manager → end hidden PowerShell running `Admin-Setup.ps1`.
Remove Run values `AdminSetupHideTaskbar` and `AdminSetupFolderLogo` if you do not want them at logon.

Old helper files (`Hide-Taskbar.ps1`, `Show-FolderLogo.ps1`, `Clear-Apps-And-Tray.ps1`) are no longer used.
