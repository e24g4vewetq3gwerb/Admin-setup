# Admin Setup

**Current version:** `20260919k` (badges: three-circle WPF bar with green trash)

Removes removable programs, hides the Windows taskbar, and leaves three launch badges at the bottom of the screen.

Win key still opens Start. No reboot.

## How it looks

A transparent bar sits at the bottom center of the primary display. Three HD circles:

| Badge | Color | Click |
| --- | --- | --- |
| Folder | dark circle, gold ring, Explorer icon | Opens your user profile folder |
| PowerShell | dark blue circle, blue ring, PowerShell icon | Opens a new PowerShell window |
| Wipe | dark green circle, green ring, **trash can** | Asks **Confirm wipe? Yes / No** (default No). Yes → UAC → uninstall removable apps, keep the taskbar hidden, then a report window |

Chrome and Grok badges are **not** in this version.

```
        [ folder ]     [ PowerShell ]     [ trash ]
                         bottom center
```

The real taskbar (`Shell_TrayWnd`) is hidden. Clock, search, and tray icons stay gone while `Hide-Taskbar.ps1` is running.

## What the wipe does

1. Walks installed programs in the Uninstall registry.
2. Skips drivers, Visual C++, .NET, Edge, Windows updates, and other protected names.
3. Runs each QuietUninstall / Uninstall string silently and waits for it to finish.
4. Removes removable Store apps for all users (keeps Store, Terminal, Edge, system packages).
5. Re-applies taskbar hide + starts the three badges.
6. Opens a dark report window: Found / Cleared / Kept / Failed.

## Files

| File | Role |
| --- | --- |
| `Clear-Apps-And-Tray.ps1` | Wipe + hide taskbar + start badges |
| `Hide-Taskbar.ps1` | Keeps `Shell_TrayWnd` hidden |
| `Show-FolderLogo.ps1` | Three circular badges |

Copies live in `%USERPROFILE%\admin\` and also start at logon via Run keys `AdminSetupHideTaskbar` and `AdminSetupFolderLogo`.

## First run

```powershell
$admin = "$env:USERPROFILE\admin"
New-Item -ItemType Directory -Force -Path $admin | Out-Null
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Clear-Apps-And-Tray.ps1 -OutFile "$admin\Clear-Apps-And-Tray.ps1"
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Hide-Taskbar.ps1 -OutFile "$admin\Hide-Taskbar.ps1"
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Show-FolderLogo.ps1 -OutFile "$admin\Show-FolderLogo.ps1"
Unblock-File "$admin\Clear-Apps-And-Tray.ps1","$admin\Hide-Taskbar.ps1","$admin\Show-FolderLogo.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$admin\Clear-Apps-And-Tray.ps1"
```

Hide the taskbar and show badges **without** uninstalling apps:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\admin\Clear-Apps-And-Tray.ps1" -SkipWipe
```

Reload badges only:

```powershell
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -like '*Show-FolderLogo.ps1*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
powershell -STA -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$env:USERPROFILE\admin\Show-FolderLogo.ps1"
```

## Stop

Task Manager → end the hidden PowerShell processes running `Hide-Taskbar.ps1` and `Show-FolderLogo.ps1`.
Remove Run values `AdminSetupHideTaskbar` and `AdminSetupFolderLogo` if you do not want them at logon.
