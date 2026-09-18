# Admin PC scripts

Private tooling for IT admin workstation hardening and related ops.

## Harden-ITAdminPC.ps1

Audit or apply Windows hardening baseline.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Harden-ITAdminPC.ps1 -Audit
powershell -ExecutionPolicy Bypass -File .\scripts\Harden-ITAdminPC.ps1 -Apply
```

Opt-in: `-EnableBitLocker`, `-DisableRDP`, `-CreateStandardUser Name`
