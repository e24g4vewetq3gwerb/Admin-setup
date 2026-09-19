<#
.SYNOPSIS
  Remove Admin Setup from this PC: badges, taskbar hider, Run keys, scripts.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'

function Test-IsAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-SelfPath {
  foreach ($c in @($PSCommandPath, $MyInvocation.MyCommand.Path)) {
    if ($c -and (Test-Path -LiteralPath "$c")) { return "$c" }
  }
  return $null
}

if (-not (Test-IsAdmin)) {
  $self = Get-SelfPath
  if ($self) {
    Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$self`"") | Out-Null
    return
  }
}

Write-Host 'Stopping Admin Setup processes'
Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID } | ForEach-Object {
  try {
    $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)" -ErrorAction SilentlyContinue).CommandLine
    if ($cmd -and ($cmd -like '*Clear-Apps-And-Tray.ps1*' -or $cmd -like '*Wipe-All-Except-Windows.ps1*' -or $cmd -like '*Admin-Setup.ps1*' -or $cmd -like '*Uninstall-AdminSetup.ps1*')) {
      Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
  } catch {}
}

$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
foreach ($name in @('AdminSetupHideTaskbar','AdminSetupFolderLogo','AdminSetupTray')) {
  try { Remove-ItemProperty -Path $runKey -Name $name -Force -ErrorAction SilentlyContinue } catch {}
}

$pol = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
foreach ($name in @('NoTrayItemsDisplay','HideClock','HideSCAHealth','HideSCAMeetNow','HideSCANetwork','HideSCAVolume','HideSCAPower','NoAutoTrayNotify','NoSetTaskbar','NoTrayContextMenu')) {
  try { Remove-ItemProperty -Path $pol -Name $name -Force -ErrorAction SilentlyContinue } catch {}
}

$adminDir = Join-Path $env:USERPROFILE 'admin'
foreach ($name in @('Clear-Apps-And-Tray.ps1','Wipe-All-Except-Windows.ps1','Admin-Setup.ps1','Uninstall-AdminSetup.ps1')) {
  $p = Join-Path $adminDir $name
  if (Test-Path -LiteralPath $p) {
    Write-Host "Delete $p"
    try { Remove-Item -LiteralPath $p -Force } catch {}
  }
}

# Show taskbar again
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class TrayShow {
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern IntPtr FindWindow(string c, string w);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool EnableWindow(IntPtr h, bool e);
  public static void Show() {
    IntPtr a = FindWindow("Shell_TrayWnd", null);
    if (a != IntPtr.Zero) { ShowWindow(a, 5); EnableWindow(a, true); }
    IntPtr b = FindWindow("Shell_SecondaryTrayWnd", null);
    if (b != IntPtr.Zero) { ShowWindow(b, 5); EnableWindow(b, true); }
  }
}
'@
try { [TrayShow]::Show() } catch {}

Write-Host 'Admin Setup removed. Taskbar should be visible. Restart Explorer if it is not.'
try { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Seconds 2
Start-Process explorer.exe | Out-Null
Write-Host 'Done.'
