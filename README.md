# Admin Setup

One Windows script. One README. One desktop icon.

Repo: [e24g4vewetq3gwerb/Admin-setup](https://github.com/e24g4vewetq3gwerb/Admin-setup)

## What it does

1. Copies itself to `%USERPROFILE%\\admin\\Admin-Setup.ps1`
2. Creates **Admin Setup** on the Desktop and in Start (Run as administrator)
3. Asks **Yes / No** for latest **Grok Bot** and **Google Chrome**
4. On **Yes**, downloads and installs **now** (still elevated — not after reboot)
5. Optional wipe of removable apps (drivers / runtimes / Chrome / Grok Bot kept)
6. Restarts only after that work is done (`-Restart` / `-RestartIfNeeded`)

The old pack asked about two downloads, then rebooted, then RunOnce often failed so **Yes did nothing**. That path is gone.

## Run

From an elevated PowerShell, after you save `Admin-Setup.ps1`:

```powershell
powershell -ExecutionPolicy Bypass -File .\\Admin-Setup.ps1 -Apply -UninstallNotKept -RestartIfNeeded
```

Icon only:

```powershell
powershell -ExecutionPolicy Bypass -File .\\Admin-Setup.ps1 -IconOnly
```

Offer apps, skip wipe:

```powershell
powershell -ExecutionPolicy Bypass -File .\\Admin-Setup.ps1 -SkipWipe
```

Cancel a pending reboot: `shutdown /a`

Log: `%USERPROFILE%\\admin\\Admin-Setup.log`

## One-liner (download from GitHub)

```powershell
irm https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Admin-Setup.ps1 -OutFile "$env:USERPROFILE\\admin\\Admin-Setup.ps1"; powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\\admin\\Admin-Setup.ps1" -Apply -UninstallNotKept -RestartIfNeeded
```

Create `%USERPROFILE%\\admin` first if needed:

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\\admin" | Out-Null
```
