<#
.SYNOPSIS
  Blank wallpaper + empty desktop (no icons, including Recycle Bin).

.DESCRIPTION
  - Sets desktop background to solid black (clears wallpaper image)
  - Hides all desktop icons (HideIcons=1) including Recycle Bin CLSID
  - Deletes files/folders on the user Desktop and Public Desktop (keeps Admin Setup.lnk)
  - Restarts Explorer so the change shows immediately

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Clear-Desktop.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Clear-Desktop.ps1 -Audit
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [switch]$Audit,
  [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
if (-not $Audit -and -not $Apply) { $Apply = $true }

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $here 'Clear-Desktop.log'
function L([string]$m) {
  $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $m
  New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
  $line | Tee-Object -FilePath $log -Append
}

L "==== Clear-Desktop Audit=$Audit Apply=$Apply ===="

$desk = 'HKCU:\Control Panel\Desktop'
$colors = 'HKCU:\Control Panel\Colors'
$adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$hide = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel'
$clsids = @(
  '{645FF040-5081-101B-9F08-00AA002F954E}', # Recycle Bin
  '{20D04FE0-3AEA-1069-A2D8-08002B30309D}', # This PC
  '{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}', # Network
  '{5399E694-6CE5-4A6C-8CC9-E579ADE8C3EF}', # Control Panel
  '{59031a47-3f72-44a7-89c5-5595fe6b30ee}'  # User Files
)

$wp = $null
try { $wp = (Get-ItemProperty -Path $desk -Name Wallpaper -EA SilentlyContinue).Wallpaper } catch {}
$hideIcons = $null
try { $hideIcons = (Get-ItemProperty -Path $adv -Name HideIcons -EA SilentlyContinue).HideIcons } catch {}
$userDesk = [Environment]::GetFolderPath('Desktop')
$publicDesk = Join-Path $env:PUBLIC 'Desktop'
$userItems = @()
if (Test-Path $userDesk) { $userItems = @(Get-ChildItem $userDesk -Force -EA SilentlyContinue) }
$pubItems = @()
if (Test-Path $publicDesk) { $pubItems = @(Get-ChildItem $publicDesk -Force -EA SilentlyContinue) }

if ($Audit) {
  L "Wallpaper='$wp' HideIcons=$hideIcons userDesktopItems=$($userItems.Count) publicDesktopItems=$($pubItems.Count)"
  Write-Host "Wallpaper: $(if ([string]::IsNullOrWhiteSpace($wp)) { 'blank/OK' } else { $wp })"
  Write-Host "HideIcons: $hideIcons (want 1)"
  Write-Host "User Desktop items: $($userItems.Count)"
  Write-Host "Public Desktop items: $($pubItems.Count)"
  exit 0
}

if ($PSCmdlet.ShouldProcess('Desktop', 'Clear wallpaper, hide icons, delete desktop items')) {
  if (-not (Test-Path $desk)) { New-Item -Path $desk -Force | Out-Null }
  New-ItemProperty -Path $desk -Name Wallpaper -PropertyType String -Value '' -Force | Out-Null
  New-ItemProperty -Path $desk -Name WallpaperStyle -PropertyType String -Value '0' -Force | Out-Null
  New-ItemProperty -Path $desk -Name TileWallpaper -PropertyType String -Value '0' -Force | Out-Null
  if (-not (Test-Path $colors)) { New-Item -Path $colors -Force | Out-Null }
  New-ItemProperty -Path $colors -Name Background -PropertyType String -Value '0 0 0' -Force | Out-Null

  $themeDir = Join-Path $env:APPDATA 'Microsoft\Windows\Themes'
  Remove-Item (Join-Path $themeDir 'TranscodedWallpaper') -Force -EA SilentlyContinue
  $cached = Join-Path $themeDir 'CachedFiles'
  if (Test-Path $cached) { Remove-Item "$cached\*" -Force -EA SilentlyContinue }

  Add-Type @"
using System.Runtime.InteropServices;
public class AdminWallpaper {
  [DllImport("user32.dll", SetLastError=true)]
  public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@ -ErrorAction SilentlyContinue
  try { [AdminWallpaper]::SystemParametersInfo(0x0014, 0, '', 0x01 -bor 0x02) | Out-Null } catch {}
  L 'Wallpaper cleared (solid black)'

  if (-not (Test-Path $adv)) { New-Item -Path $adv -Force | Out-Null }
  New-ItemProperty -Path $adv -Name HideIcons -PropertyType DWord -Value 1 -Force | Out-Null
  if (-not (Test-Path $hide)) { New-Item -Path $hide -Force | Out-Null }
  foreach ($c in $clsids) {
    New-ItemProperty -Path $hide -Name $c -PropertyType DWord -Value 1 -Force | Out-Null
  }
  L 'Desktop icons hidden (including Recycle Bin)'

  foreach ($d in @($userDesk, $publicDesk)) {
    if (-not (Test-Path $d)) { continue }
    Get-ChildItem $d -Force -EA SilentlyContinue | ForEach-Object {
      # Keep the Admin Setup launcher icon
      if ($_.Name -eq 'Admin Setup.lnk' -or $_.Name -eq 'desktop.ini') {
        L "KEEP $($_.FullName)"
        return
      }
      try {
        Remove-Item $_.FullName -Recurse -Force -EA Stop
        L "REMOVED $($_.FullName)"
      } catch {
        L "FAIL $($_.FullName): $($_.Exception.Message)"
      }
    }
  }

  try {
    Get-Process explorer -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -EA SilentlyContinue)) { Start-Process explorer.exe }
    L 'Explorer restarted'
  } catch {
    L "Explorer restart: $($_.Exception.Message)"
  }
}

L '==== Clear-Desktop finished ===='
Write-Host 'Desktop cleared: black background, no icons (Recycle Bin hidden), folders emptied.'
Write-Host "Log: $log"
exit 0
