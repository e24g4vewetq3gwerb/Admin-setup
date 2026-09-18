# Admin PC setup

Public Windows **IT admin workstation** toolkit for a minimal, hardened personal PC.

**Keep profile:** Google Chrome, Grok Bot, Windows Terminal (plus protected drivers: Realtek audio, VC++ redistributables, Canon printer stack).

Repo: [`e24g4vewetq3gwerb/Admin-setup`](https://github.com/e24g4vewetq3gwerb/Admin-setup) (public)

---

## Quick start (elevated PowerShell)

```powershell
cd $env:USERPROFILE\admin
powershell -ExecutionPolicy Bypass -File .\scripts\Admin-Setup.ps1 -Audit
# Review CSVs, then:
powershell -ExecutionPolicy Bypass -File .\scripts\Admin-Setup.ps1 -Apply -UninstallNotKept -RestartIfNeeded
```

`Admin-Setup.ps1` is the **one-shot entrypoint**. It runs hardening, background cleanup, and Edge/Outlook/Store taskbar removal in order.

---

## What the package does

| Script | Purpose |
|--------|---------|
| **Admin-Setup.ps1** | Master setup: Harden → Cleanup → Unpin/OEM removal; `-Audit` / `-Apply` / `-UninstallNotKept` / `-Restart` / `-RestartIfNeeded` |
| **Harden-ITAdminPC.ps1** | Security baseline: UAC, Defender, firewall, SMBv1/LLMNR/AutoPlay, RDP/WinRM, audit policy, lock/sleep; optional BitLocker (Pro) |
| **Cleanup-Background.ps1** | Minimal keep list; junk services/startups; install/remove CSVs; uninstall non-kept apps; AppX junk; restart policy |
| **Unpin-And-Remove-OEM.ps1** | Unpin **Edge / Outlook / Microsoft Store** from the taskbar; remove Store + Outlook AppX; best-effort Edge uninstall |
| **Complete-Need.ps1** | Finish remaining harden NEED items (NetBIOS, SMB/RPC blocks, BitLocker attempt, Secure Boot how-to) |

### Outputs

- `Cleanup-Background-Programs.csv` / `KeepList.csv` / `RemoveCandidates.csv`
- `Harden-ITAdminPC.csv` / `.log`
- `Cleanup-EdgeOutlookStore.csv`
- `SecureBoot-HOW-TO.txt`

---

## Design rules

1. Run `-Audit` before destructive uninstalls.
2. Never disable Defender / SecurityHealth / core Windows services.
3. BitLocker full features need Windows Pro; Home may use Device encryption only.
4. Secure Boot is firmware-only.
5. `-RestartIfNeeded` schedules a 60–90s reboot when changes were made (`shutdown /a` cancels).

---

## Typical first-time admin setup

1. Sync this repo to `%USERPROFILE%\admin`.
2. `Admin-Setup.ps1 -Audit` and review CSVs.
3. `Admin-Setup.ps1 -Apply -UninstallNotKept -RestartIfNeeded` (approve UAC).
4. After reboot: confirm Chrome + Grok Bot + Terminal; Edge/Store/Outlook off the taskbar.
5. Optional: Secure Boot in UEFI; Device encryption on Home.

---

## Portfolio note

Documents a practical **endpoint hardening + minimal desktop** workflow for an IT-admin style workstation.
