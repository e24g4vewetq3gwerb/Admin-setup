# Admin PC setup

Public Windows **IT admin workstation** toolkit for a minimal, hardened personal PC.

**Desktop goal (default):** after setup / reboot, taskbar shows only the **Windows Start** button and the **up-arrow Show Hidden Icons** chevron — no Chrome / Cursor / Grok pins, no tray clutter.

**Optional legacy dock:** `-DockChromeCursorGrok` pins Google Chrome, Cursor, and Grok Bot (centered).

**Uninstall keep list (unchanged):** Google Chrome, Grok / Grok Bot, Windows Terminal (plus protected drivers: Realtek audio, VC++ redistributables, Canon printer stack). Startup folders/Run keys are cleared bare (no special Chrome/Grok keep); SecurityHealth stays protected.

**System tray goal:** only the **up-arrow Show Hidden Icons** chevron on the right (language, Wi‑Fi, volume, battery, and Show Desktop hidden via Windhawk).

**Installed apps count:** `Cleanup-Background.ps1` prints `Installed apps (Settings-style): N apps found` (Win32 uninstall registry + visible current-user AppX), matching Settings → Apps → Installed apps roughly; Win32-only count still goes to `Cleanup-Background-Programs.csv`.

Repo: [`e24g4vewetq3gwerb/Admin-setup`](https://github.com/e24g4vewetq3gwerb/Admin-setup) (public)

![Admin setup activity flowchart](docs/admin-setup-flowchart.png)

---

## Quick start (elevated PowerShell)

```powershell
cd $env:USERPROFILE\admin
powershell -ExecutionPolicy Bypass -File .\scripts\Admin-Setup.ps1 -Audit
# Review CSVs (including Settings-style app count in cleanup output), then:
powershell -ExecutionPolicy Bypass -File .\scripts\Admin-Setup.ps1 -Apply -UninstallNotKept -RestartIfNeeded
```

`Admin-Setup.ps1` is the **one-shot entrypoint**. It runs hardening, background cleanup, OEM unpin, and the minimal taskbar (Start + up-arrow by default, including Windhawk up-arrow-only tray) in order.

### Legacy 3-app dock (optional)

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Admin-Setup.ps1 -Apply -DockChromeCursorGrok
```

### Tray only (Windhawk up-arrow chevron)

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Restore-TrayArrowOnly.ps1
```

---

## Activity flow (template)

```
Admin-Setup.ps1
   ├─ -Audit   → report only (CSVs + Settings-style app count)
   ├─ -Apply   → Harden → Cleanup → Unpin OEM → Minimal taskbar (StartOnly + Windhawk)
   ├─ -DockChromeCursorGrok → optional legacy Chrome/Cursor/Grok pins
   └─ -RestartIfNeeded → reboot if Apply ran cleanup/taskbar (`shutdown /r /t 60`)

Optional: Complete-Need.ps1 (finish NEED items / Secure Boot how-to)
Optional: Restore-TrayArrowOnly.ps1 (re-apply up-arrow-only tray)
```

| Stage | Script | Activity |
|-------|--------|----------|
| 1 | **Harden-ITAdminPC.ps1** | Security baseline (UAC, Defender, firewall, SMB/LLMNR, RDP/WinRM, lock) |
| 2 | **Cleanup-Background.ps1** | Minimal keep list for uninstall; Settings-style app count; bare startup clear; service cleanup |
| 3 | **Unpin-And-Remove-OEM.ps1** | Unpin Edge / Outlook / Store; remove OEM AppX |
| 4 | **Minimal-Taskbar.ps1** | Default **StartOnly**: clear all pins, left-align Start; hide widgets/search/task view; Windhawk up-arrow-only tray |
| * | **Restore-TrayArrowOnly.ps1** | Standalone: Windhawk `taskbar-tray-system-icon-tweaks` → tray shows only up-arrow |
| * | **Offer-GrokBot.ps1** | After restart/logon: if Grok Bot missing, ask Yes/No and download installer from cursor.com |
| * | **Complete-Need.ps1** | Optional: NetBIOS, SMB/RPC blocks, BitLocker attempt, Secure Boot notes |

---

## What the package does

| Script | Purpose |
|--------|---------|
| **Admin-Setup.ps1** | Master setup: Harden → Cleanup → Unpin/OEM → Minimal taskbar; `-StartOnly` (default), `-DockChromeCursorGrok`, `-SkipWindhawkTray` |
| **Harden-ITAdminPC.ps1** | Security baseline: UAC, Defender, firewall, SMBv1/LLMNR/AutoPlay, RDP/WinRM, audit policy, lock/sleep; optional BitLocker (Pro) |
| **Cleanup-Background.ps1** | Minimal uninstall keep list; junk services; **Settings-style installed-app count**; bare startup clear; uninstall non-kept apps; AppX junk; restart policy |
| **Unpin-And-Remove-OEM.ps1** | Unpin **Edge / Outlook / Microsoft Store** from the taskbar; remove Store + Outlook AppX; best-effort Edge uninstall |
| **Minimal-Taskbar.ps1** | Hide Widgets/Search/Task View/Chat; **default clear all pins + left align**; optional `-DockChromeCursorGrok`; Windhawk tray on `-Apply` |
| **Restore-TrayArrowOnly.ps1** | Install/configure Windhawk mod so Control Center icons hide; **keep up-arrow chevron** |
| **Complete-Need.ps1** | Finish remaining harden NEED items (NetBIOS, SMB/RPC blocks, BitLocker attempt, Secure Boot how-to) |

### Key switches

| Switch | Where | Effect |
|--------|-------|--------|
| `-StartOnly` | Minimal-Taskbar / Admin-Setup | Clear all taskbar `.lnk` pins; `TaskbarAl=0` (default on Apply) |
| `-DockChromeCursorGrok` | Minimal-Taskbar / Admin-Setup | Legacy: pin Chrome, Cursor, Grok Bot; center align |
| `-SkipWindhawkTray` | Both | Skip Windhawk up-arrow-only tray configure |
| `-Restart` / `-RestartIfNeeded` | Admin-Setup / Cleanup | Schedule `shutdown /r /t 60` |

### Outputs

- `Cleanup-Background-Programs.csv` / `KeepList.csv` / `RemoveCandidates.csv`
- `Cleanup-Background-SettingsStyleApps.csv` (Settings-style total)
- `Harden-ITAdminPC.csv` / `.log`
- `Cleanup-EdgeOutlookStore.csv`
- `Minimal-Taskbar.csv` / `.log`
- `SecureBoot-HOW-TO.txt`

---

## Design rules

1. Run `-Audit` before destructive uninstalls.
2. Never disable Defender / SecurityHealth / core Windows services.
3. BitLocker full features need Windows Pro; Home may use Device encryption only.
4. Secure Boot is firmware-only.
5. `-RestartIfNeeded` schedules a 60s reboot when Apply ran cleanup/taskbar (`shutdown /a` cancels).
6. On Windows 11 25H2, classic `HideSCA*` policies do **not** hide Control Center tray icons (language / Wi‑Fi / volume / battery). Use **Windhawk** + `taskbar-tray-system-icon-tweaks`.
7. Do **not** set `NoTrayItemsDisplay=1` if you want to keep the up-arrow overflow chevron.
8. Windhawk mod `Include` must be **REG_SZ** `explorer.exe` (REG_MULTI_SZ breaks injection on this setup).
9. Default UI goal is **Start + up-arrow only**; keep Chrome/Grok/Terminal on the uninstall keep list but do not pin them unless `-DockChromeCursorGrok`.

---

## Typical first-time admin setup

1. Sync this repo to `%USERPROFILE%\admin`.
2. `Admin-Setup.ps1 -Audit` and review CSVs; note `Installed apps (Settings-style): N apps found`.
3. `Admin-Setup.ps1 -Apply -UninstallNotKept -RestartIfNeeded` (approve UAC; allow Windhawk install if prompted).
4. After reboot: confirm **only Start** on the left and **only up-arrow** on the right tray — no Chrome/Cursor/Grok pins.
5. If tray icons return: `Restore-TrayArrowOnly.ps1` as admin.
6. Optional: `-DockChromeCursorGrok` if you want the old 3-app dock; Secure Boot in UEFI; Device encryption on Home.

---

## Portfolio note

Documents a practical **endpoint hardening + minimal desktop** workflow for an IT-admin style workstation, including a Windhawk-based Win11 system-tray cleanup and a Start-only taskbar profile.


### Post-restart Grok Bot offer

When `Admin-Setup.ps1` or `Cleanup-Background.ps1` schedules a reboot (`-Restart` / `-RestartIfNeeded`), it registers a one-time **RunOnce** that runs `Offer-GrokBot.ps1` at next logon:

1. If Grok Bot is already installed → quiet exit.
2. If missing → MessageBox: download now?
3. On Yes → download Windows Setup from [cursor.com/download/bot](https://cursor.com/download/bot) and run it.

Manual: `powershell -ExecutionPolicy Bypass -File .\scripts\Offer-GrokBot.ps1`
Register only: `... Offer-GrokBot.ps1 -RegisterRunOnce`
