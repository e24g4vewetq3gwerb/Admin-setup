@echo off
:: One-click Admin wipe setup (elevated). Ask for Grok+Chrome only AFTER restart.
set SCRIPT_DIR=%~dp0
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%SCRIPT_DIR%Admin-Setup.ps1\" -Apply -UninstallNotKept -RestartIfNeeded -KeepProfile DriversOnly'"
