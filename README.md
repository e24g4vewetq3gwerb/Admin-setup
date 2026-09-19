# Clear apps and remove the taskbar

Uninstall removable apps. Hide `Shell_TrayWnd` so the taskbar is gone.

No Start overlay. No reboot. Win key still opens Start.

## Run

```powershell
$admin = "$env:USERPROFILE\admin"
New-Item -ItemType Directory -Force -Path $admin | Out-Null
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Clear-Apps-And-Tray.ps1 -OutFile "$admin\Clear-Apps-And-Tray.ps1"
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Hide-Taskbar.ps1 -OutFile "$admin\Hide-Taskbar.ps1"
Unblock-File "$admin\Clear-Apps-And-Tray.ps1","$admin\Hide-Taskbar.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$admin\Clear-Apps-And-Tray.ps1" -SkipWipe
```

Stop the hide helper: Task Manager → end the hidden PowerShell running `Hide-Taskbar.ps1`.
