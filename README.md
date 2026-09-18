# Admin PC setup

Public Windows **IT admin workstation** toolkit for a minimal, hardened personal PC.

**Keep / dock profile:** Google Chrome, Cursor, Grok Bot (plus protected drivers: Realtek audio, VC++ redistributables, Canon printer stack).

**System tray goal:** only the **↑ Show Hidden Icons** chevron on the right (language, Wi‑Fi, volume, battery, and Show Desktop hidden via Windhawk).

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

`Admin-Setup.ps1` is the **one-shot entrypoint**. It runs hardening, background cleanup, OEM unpin, and the minimal taskbar dock (including Windhawk ↑-only tray) in order.

### Tray only (Windhawk ↑ chevron)

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Restore-TrayArrowOnly.ps1
```

---

## Activity flow (template)

```
Admin-Setup.ps1
   ├─ -Audit   → report only (CSVs)
   ├─ -Apply   → Harden → Cleanup → Unpin OEM → Minimal taskbar (+ Windhawk tray)
   └─ -RestartIfNeeded → reboot if changes require it

Optional: Complete-Need.ps1 (finish NEED items / Secure Boot how-to)
Optional: Restore-TrayArrowOnly.ps1 (re-apply ↑-only tray)
```

| Stage | Script | Activity |
|-------|--------|----------|
| 1 | **Harden-ITAdminPC.ps1** | Security baseline (UAC, Defender, firewall, SMB/LLMNR, RDP/WinRM, lock) |
| 2 | **Cleanup-Background.ps1** | Minimal desktop; uninstall non-kept apps; service/startup cleanup |
| 3 | **Unpin-And-Remove-OEM.ps1** | Unpin Edge / Outlook / Store; remove OEM AppX |
| 4 | **Minimal-Taskbar.ps1** | Dock: Chrome / Cursor / Grok Bot; hide widgets/search/task view; Windhawk ↑-only tray |
| * | **Restore-TrayArrowOnly.ps1** | Standalone: Windhawk `taskbar-tray-system-icon-tweaks` → tray shows only ↑ |
| * | **Complete-Need.ps1** | Optional: NetBIOS, SMB/RPC blocks, BitLocker attempt, Secure Boot notes |

---

## What the package does

| Script | Purpose |
|--------|---------|
| **Admin-Setup.ps1** | Master setup: Harden → Cleanup → Unpin/OEM → Minimal taskbar; `-SkipWindhawkTray` available |
| **Harden-ITAdminPC.ps1** | Security baseline: UAC, Defender, firewall, SMBv1/LLMNR/AutoPlay, RDP/WinRM, audit policy, lock/sleep; optional BitLocker (Pro) |
| **Cleanup-Background.ps1** | Minimal keep list; junk services/startups; install/remove CSVs; uninstall non-kept apps; AppX junk; restart policy |
| **Unpin-And-Remove-OEM.ps1** | Unpin **Edge / Outlook / Microsoft Store** from the taskbar; remove Store + Outlook AppX; best-effort Edge uninstall |
| **Minimal-Taskbar.ps1** | Hide Widgets/Search/Task View/Chat; center icons; keep pins for Chrome, Cursor, Grok Bot; call Windhawk tray restore on `-Apply` |
| **Restore-TrayArrowOnly.ps1** | Install/configure Windhawk mod so Control Center icons hide; **keep ↑ chevron** |
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
6. On Windows 11 25H2, classic `HideSCA*` policies do **not** hide Control Center tray icons (language / Wi‑Fi / volume / battery). Use **Windhawk** + `taskbar-tray-system-icon-tweaks`.
7. Do **not** set `NoTrayItemsDisplay=1` if you want to keep the ↑ overflow chevron.
8. Windhawk mod `Include` must be **REG_SZ** `explorer.exe` (REG_MULTI_SZ breaks injection on this setup).

---

## Typical first-time admin setup

1. Sync this repo to `%USERPROFILE%\admin`.
2. `Admin-Setup.ps1 -Audit` and review CSVs.
3. `Admin-Setup.ps1 -Apply -UninstallNotKept -RestartIfNeeded` (approve UAC; allow Windhawk install if prompted).
4. After reboot: confirm Chrome + Cursor + Grok Bot centered; right tray shows **only ↑**.
5. If tray icons return: `Restore-TrayArrowOnly.ps1` as admin.
6. Optional: Secure Boot in UEFI; Device encryption on Home.

---

## Portfolio note

Documents a practical **endpoint hardening + minimal desktop** workflow for an IT-admin style workstation, including a Windhawk-based Win11 system-tray cleanup.
