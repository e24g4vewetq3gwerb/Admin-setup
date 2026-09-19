<#
.SYNOPSIS
  Keep the Windows taskbar window hidden. Does not open Start.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'

$mutex = New-Object System.Threading.Mutex($false, 'Local\AdminSetupHideTaskbar')
if (-not $mutex.WaitOne(0, $false)) { return }

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class TrayHide {
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr child, string cls, string win);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool EnableWindow(IntPtr hWnd, bool enable);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
  const int SW_HIDE = 0;
  const uint SWP_HIDEWINDOW = 0x0080;
  const uint SWP_NOSIZE = 0x0001;
  const uint SWP_NOMOVE = 0x0002;
  const uint SWP_NOZORDER = 0x0004;
  public static void HideAll() {
    HideOne(FindWindow("Shell_TrayWnd", null));
    HideOne(FindWindow("Shell_SecondaryTrayWnd", null));
    HideOne(FindWindow("NotifyIconOverflowWindow", null));
    IntPtr start = FindWindow("Windows.UI.Core.CoreWindow", "Start");
    HideOne(start);
  }
  static void HideOne(IntPtr hwnd) {
    if (hwnd == IntPtr.Zero) return;
    ShowWindow(hwnd, SW_HIDE);
    EnableWindow(hwnd, false);
    SetWindowPos(hwnd, IntPtr.Zero, 0, 0, 0, 0, SWP_HIDEWINDOW | SWP_NOSIZE | SWP_NOMOVE | SWP_NOZORDER);
  }
}
'@

while ($true) {
  try { [TrayHide]::HideAll() } catch {}
  Start-Sleep -Milliseconds 400
}
