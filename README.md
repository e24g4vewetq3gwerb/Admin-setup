# Admin PC setup

Public Windows **IT admin workstation** toolkit for a minimal, hardened personal PC.

**Keep / dock profile:** Google Chrome, Cursor, Grok Bot (plus protected drivers: Realtek audio, VC++ redistributables, Canon printer stack). Windows Terminal may stay installed but is not pinned.

Repo: [`e24g4vewetq3gwerb/Admin-setup`](https://github.com/e24g4vewetq3gwerb/Admin-setup) (public)

![Admin setup activity flowchart](docs/admin-setup-flowchart.png)

---

## Quick start (elevated PowerShell)

```powershell
cd $env:USERPROFILE\admin
powershell -ExecutionPolicy Bypass -File .\scripts\Admin-Setup.ps1 -Audit
# Review CSVs, then:
powershell -ExecutionPolicy Bypass -File .\scripts\Admin-Setup.ps1 -Apply -UninstallNotKept -RestartIfNeeded
```

`Admin-Setup.ps1` is the **one-shot entrypoint**. It runs hardening, background cleanup, OEM unpin, and the minimal taskbar dock in order.

---

## Activity flow (template)

```
Admin-Setup.ps1
   ├─ -Audit   → report only (CSVs)
   ├─ -Apply   → Harden → Cleanup → Unpin OEM → Minimal taskbar
   └─ -RestartIfNeeded → reboot if changes require it

Optional: Complete-Need.ps1 (finish NEED items / Secure Boot how-to)
```

| Stage | Script | Activity |
|-------|--------|----------|
| 1 | **Harden-ITAdminPC.ps1** | Security baseline (UAC, Defender, firewall, SMB/LLMNR, RDP/WinRM, lock) |
| 2 | **Cleanup-Background.ps1** | Minimal desktop; uninstall non-kept apps; service/startup cleanup |
| 3 | **Unpin-And-Remove-OEM.ps1** | Unpin Edge / Outlook / Store; remove OEM AppX |
| 4 | **Minimal-Taskbar.ps1** | Dock look: only Chrome / Cursor / Grok Bot; hide widgets, search, task view, overflow tray (^) |
| * | **Complete-Need.ps1** | Optional: NetBIOS, SMB/RPC blocks, BitLocker attempt, Secure Boot notes |

---

## What the package does

| Script | Purpose |
|--------|---------|
| **Admin-Setup.ps1** | Master setup: Harden → Cleanup → Unpin/OEM → Minimal taskbar; `-Audit` / `-Apply` / `-UninstallNotKept` / `-Restart` / `-RestartIfNeeded` / `-SkipTaskbar` |
| **Harden-ITAdminPC.ps1** | Security baseline: UAC, Defender, firewall, SMBv1/LLMNR/AutoPlay, RDP/WinRM, audit policy, lock/sleep; optional BitLocker (Pro) |
| **Cleanup-Background.ps1** | Minimal keep list; junk services/startups; install/remove CSVs; uninstall non-kept apps; AppX junk; restart policy |
| **Unpin-And-Remove-OEM.ps1** | Unpin **Edge / Outlook / Microsoft Store** from the taskbar; remove Store + Outlook AppX; best-effort Edge uninstall |
| **Minimal-Taskbar.ps1** | Hide Widgets/Search/Task View/Chat; center icons; hide overflow tray icons (`NoTrayItemsDisplay`); keep pin shortcuts for Chrome, Cursor, Grok Bot |
| **Complete-Need.ps1** | Finish remaining harden NEED items (NetBIOS, SMB/RPC blocks, BitLocker attempt, Secure Boot how-to) |

### Outputs

- `Cleanup-Background-Programs.csv` / `KeepList.csv` / `RemoveCandidates.csv`
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
5. `-RestartIfNeeded` schedules a 60–90s reboot when changes were made (`shutdown /a` cancels).
6. Windows 11 may still show clock / network / volume on the far right; overflow (^) icons are suppressed.

---

## Typical first-time admin setup

1. Sync this repo to `%USERPROFILE%\admin`.
2. `Admin-Setup.ps1 -Audit` and review CSVs.
3. `Admin-Setup.ps1 -Apply -UninstallNotKept -RestartIfNeeded` (approve UAC).
4. After reboot: confirm Chrome + Cursor + Grok Bot on the taskbar; no overflow chevron clutter.
5. Optional: Secure Boot in UEFI; Device encryption on Home.

---

## Portfolio note

Documents a practical **endpoint hardening + minimal desktop** workflow for an IT-admin style workstation.
