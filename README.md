# Clear apps and system tray

Uninstall removable apps. Taskbar shows **Start** and **Windows PowerShell** only.

Does not reboot. Refreshes the shell by stopping Explorer and letting Windows bring the taskbar back (does not open a folder window).

## Run

```powershell
$dst = "$env:USERPROFILE\admin\Clear-Apps-And-Tray.ps1"
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\admin" | Out-Null
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Clear-Apps-And-Tray.ps1 -OutFile $dst
Unblock-File $dst
powershell -NoProfile -ExecutionPolicy Bypass -File $dst
```

Layout-only: add `-SkipWipe`.
