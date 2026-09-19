@echo off
setlocal EnableExtensions
title Admin Setup bootstrap (CMD only)
echo.
echo === Admin Setup: download + run (no installs needed) ===
echo.

set "ROOT=%USERPROFILE%\admin"
mkdir "%ROOT%" 2>nul
cd /d "%ROOT%" || goto :fail

echo [1/4] Downloading from GitHub...
curl.exe -L --retry 3 --retry-delay 2 -o "%TEMP%\admin-setup.zip" "https://github.com/e24g4vewetq3gwerb/Admin-setup/archive/refs/heads/main.zip"
if errorlevel 1 (
  echo curl failed — trying PowerShell download...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri 'https://github.com/e24g4vewetq3gwerb/Admin-setup/archive/refs/heads/main.zip' -OutFile $env:TEMP\admin-setup.zip -UseBasicParsing"
  if errorlevel 1 goto :fail
)

echo [2/4] Extracting...
if exist "%TEMP%\admin-setup-extract" rd /s /q "%TEMP%\admin-setup-extract"
mkdir "%TEMP%\admin-setup-extract" 2>nul
tar.exe -xf "%TEMP%\admin-setup.zip" -C "%TEMP%\admin-setup-extract"
if errorlevel 1 (
  echo tar failed — trying Expand-Archive...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Path $env:TEMP\admin-setup.zip -DestinationPath $env:TEMP\admin-setup-extract -Force"
  if errorlevel 1 goto :fail
)

echo [3/4] Copying into %ROOT%...
robocopy "%TEMP%\admin-setup-extract\Admin-setup-main" "%ROOT%" /E /NFL /NDL /NJH /NJS /nc /ns /np >nul
if not exist "%ROOT%\scripts\Admin-Setup.ps1" (
  echo ERROR: scripts\Admin-Setup.ps1 missing after copy
  dir "%TEMP%\admin-setup-extract"
  goto :fail
)

echo [4/4] Starting Admin-Setup elevated (approve UAC)...
echo Download ask for Grok + Chrome happens AFTER restart, not now.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%ROOT%\scripts\Admin-Setup.ps1\" -Apply -UninstallNotKept -RestartIfNeeded -KeepProfile DriversOnly'"
if errorlevel 1 goto :fail

echo.
echo Launched. Approve UAC if prompted, then wait for reboot + post-login offer.
goto :eof

:fail
echo.
echo FAILED. Make sure you have internet and try again.
pause
exit /b 1
