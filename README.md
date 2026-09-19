# Admin Setup

## Clear-Apps-And-Tray.ps1

Removes removable apps, hides the taskbar, shows three badges. Opens the report window when done.

```powershell
$dst = "$env:USERPROFILE\admin\Clear-Apps-And-Tray.ps1"
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Clear-Apps-And-Tray.ps1 -OutFile $dst
Unblock-File $dst
powershell -STA -NoProfile -ExecutionPolicy Bypass -File $dst
```

## Wipe-All-Except-Windows.ps1

Separate script. **Not** connected to the trash badge.

Keeps `C:\Windows`, boot files, pagefile, and `%USERPROFILE%\admin`. Everything else on all drives is in scope.

Preview (no delete):

```powershell
$w = "$env:USERPROFILE\admin\Wipe-All-Except-Windows.ps1"
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Wipe-All-Except-Windows.ps1 -OutFile $w
powershell -NoProfile -ExecutionPolicy Bypass -File $w -WhatIf
```

Live delete (destroys documents, Program Files, other drives):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File $w -WhatIf:$false -ConfirmPhrase WIPE-ALL-DATA
```
