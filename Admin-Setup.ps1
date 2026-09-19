<#
.SYNOPSIS
  One script: wipe removable apps, hide the taskbar, show three launch badges.
.PARAMETER Mode
  All (default) | Wipe | HideBar | Badges
#>
[CmdletBinding()]
param(
  [ValidateSet('All','Wipe','HideBar','Badges')]
  [string]$Mode = 'All',
  [switch]$SkipWipe,
  [switch]$SkipTray,
  [switch]$ShowReport
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
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Test-NameLike([string]$Name, [string[]]$Patterns) {
  if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
  foreach ($pattern in $Patterns) { if ($Name -like $pattern) { return $true } }
  return $false
}

# ---- helper loops (same file, different Mode) ----
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
    $bmp.BeginInit()
    $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bmp.StreamSource = $ms
    $bmp.EndInit()
    $bmp.Freeze()
    $ms.Dispose()
    return $bmp
  }
  function Get-ExeImage([string]$Path) {
    try {
      $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($Path)
      if (-not $ico) { return $null }
      return Convert-ToBitmapSource $ico.ToBitmap()
    } catch { return $null }
  }
  $folderImg = Get-ExeImage (Join-Path $env:SystemRoot 'explorer.exe')
  $psImg = Get-ExeImage (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
  $selfPath = Get-SelfPath
  $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Launch" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ShowInTaskbar="False" Topmost="True"
        ResizeMode="NoResize" SizeToContent="WidthAndHeight"
        UseLayoutRounding="True" SnapsToDevicePixels="True">
  <StackPanel Orientation="Horizontal" Margin="8,8,8,10">
    <Grid Width="64" Height="64" Margin="0,0,18,0" Cursor="Hand" Name="BtnFolder" ToolTip="Open your folder">
      <Ellipse Fill="#FF2A2A2A" Stroke="#FFE6B422" StrokeThickness="2.2"/>
      <Image Name="ImgFolder" Width="30" Height="30" RenderOptions.BitmapScalingMode="HighQuality"/>
    </Grid>
    <Grid Width="64" Height="64" Margin="0,0,18,0" Cursor="Hand" Name="BtnPs" ToolTip="Open PowerShell">
      <Ellipse Fill="#FF172233" Stroke="#FF3B9AE1" StrokeThickness="2.2"/>
      <Image Name="ImgPs" Width="30" Height="30" RenderOptions.BitmapScalingMode="HighQuality"/>
    </Grid>
    <Grid Width="64" Height="64" Cursor="Hand" Name="BtnScript" ToolTip="Clear apps (asks first)">
      <Ellipse Fill="#FF14301F" Stroke="#FF3DDC84" StrokeThickness="2.2"/>
      <Viewbox Width="30" Height="30">
        <Canvas Width="48" Height="48">
          <Path Fill="#FF3DDC84" Data="M 10,16 L 38,16 L 36,42 L 12,42 Z"/>
          <Path Fill="#FF0E1C14" Data="M 18,16 L 18,42 M 24,16 L 24,42 M 30,16 L 30,42" Stroke="#FF0E1C14" StrokeThickness="2"/>
          <Path Fill="#FF3DDC84" Data="M 8,12 L 40,12 L 40,16 L 8,16 Z"/>
          <Path Fill="#FF3DDC84" Data="M 18,6 L 30,6 L 32,12 L 16,12 Z"/>
        </Canvas>
      </Viewbox>
    </Grid>
  </StackPanel>
</Window>
'@
  $window = [Windows.Markup.XamlReader]::Parse($xaml)
  $window.FindName('ImgFolder').Source = $folderImg
  $window.FindName('ImgPs').Source = $psImg
  function Move-ToBottom {
    $sw = [System.Windows.SystemParameters]::PrimaryScreenWidth
    $sh = [System.Windows.SystemParameters]::PrimaryScreenHeight
    $window.Left = [Math]::Max(0, ($sw - $window.ActualWidth) / 2)
    $window.Top = $sh - $window.ActualHeight - 16
  }
  function Confirm-AndRun {
    if (-not $selfPath -or -not (Test-Path -LiteralPath $selfPath)) {
      [System.Windows.MessageBox]::Show('Script file not found.', 'Admin Setup', 'OK', 'Warning') | Out-Null
      return
    }
    $answer = [System.Windows.MessageBox]::Show(
      "Run Clear Apps and Tray again?`n`nThis will uninstall removable programs and keep the taskbar hidden.`nA report opens when it finishes.`n`nContinue?",
      'Confirm wipe', 'YesNo', 'Exclamation', 'No')
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Start-Process -FilePath $ps -Verb RunAs -ArgumentList @(
      '-STA','-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$selfPath`"",'-Mode','Wipe'
    ) | Out-Null
  }
  $window.FindName('BtnFolder').Add_MouseLeftButtonUp({
    Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList @("`"$env:USERPROFILE`"") | Out-Null
  })
  $window.FindName('BtnPs').Add_MouseLeftButtonUp({
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') | Out-Null
  })
  $window.FindName('BtnScript').Add_MouseLeftButtonUp({ Confirm-AndRun })
  $window.Add_ContentRendered({ Move-ToBottom })
  $timer = New-Object System.Windows.Threading.DispatcherTimer
  $timer.Interval = [TimeSpan]::FromSeconds(3)
  $timer.Add_Tick({ $window.Topmost = $true; Move-ToBottom })
  $timer.Start()
  [void]$window.ShowDialog()
  return
}

# ---- main: wipe + install helpers ----
$homeRoot = Join-Path $env:USERPROFILE 'admin'
New-Item -ItemType Directory -Force -Path $homeRoot | Out-Null
$log = Join-Path $homeRoot 'Admin-Setup.log'
$script:ReportKept = New-Object System.Collections.Generic.List[string]
$script:ReportCleared = New-Object System.Collections.Generic.List[string]
$script:ReportFailed = New-Object System.Collections.Generic.List[string]
$script:ReportFound = 0
function Write-Log([string]$Message) {
  $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message
  try { $line | Tee-Object -FilePath $log -Append } catch { Write-Host $line }
}
Write-Log 'Admin-Setup 20260919 one-file'

if (-not (Test-IsAdmin)) {
  $self = Get-SelfPath
  if (-not $self) { $self = $MyInvocation.MyCommand.Definition }
  $arg = @('-STA','-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$self`"",'-Mode',$Mode)
  if ($SkipWipe) { $arg += '-SkipWipe' }
  if ($SkipTray) { $arg += '-SkipTray' }
  if ($ShowReport) { $arg += '-ShowReport' }
  Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList $arg | Out-Null
  return
}

function Install-Self {
  $self = Get-SelfPath
  $dest = Join-Path $homeRoot 'Admin-Setup.ps1'
  if ($self -and (Test-Path -LiteralPath $self)) {
    if ([IO.Path]::GetFullPath($self) -ne [IO.Path]::GetFullPath($dest)) {
      Copy-Item -LiteralPath $self -Destination $dest -Force
    }
  }
  return $dest
}
function Start-Mode([string]$Path, [string]$HelperMode, [string]$RunName, [switch]$Sta) {
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
  New-Item -Path $runKey -Force | Out-Null
  $staBit = if ($Sta) { '-STA ' } else { '' }
  $cmd = "`"$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe`" $staBit-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Path`" -Mode $HelperMode"
  New-ItemProperty -Path $runKey -Name $RunName -Value $cmd.Trim() -PropertyType String -Force | Out-Null
  $args = @('-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',"`"$Path`"",'-Mode',$HelperMode)
  if ($Sta) { $args = @('-STA') + $args }
  Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -WindowStyle Hidden -ArgumentList $args | Out-Null
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
    $low = "$args".ToLowerInvariant()
    if ($low -notmatch '/s\b|/silent|/quiet|/qn|/norestart') { $args = ("$args /S /silent /quiet /norestart").Trim() }
    $p = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
    return ($null -eq $p.ExitCode -or $p.ExitCode -in 0, 1, 1605, 1614, 1641, 3010)
  } catch { return $false }
}
function Invoke-ClearWin32Apps {
  $protect = @('Microsoft Visual C++*','Microsoft Visual Studio* Redistributable*','Microsoft .NET*','Microsoft Edge*','Microsoft Edge WebView2*','Microsoft Update*','Windows PC Health Check*','Update for *','Security Update*','Hotfix*','Intel*','NVIDIA*','AMD*','Chipset*','Canon *','HP *','Printer*','Driver*','Windows Terminal*','Windows SDK*','Microsoft Windows*','Windows Malicious Software Removal*')
  $force = @('Realtek*')
  $paths = @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')
  $removed = 0
  foreach ($prog in @(Get-ItemProperty $paths -ErrorAction SilentlyContinue)) {
    $name = [string](Get-Prop $prog 'DisplayName')
    if (-not $name) { continue }
    $script:ReportFound++
    $forced = Test-NameLike $name $force
    if (-not $forced) {
      $systemComponent = Get-Prop $prog 'SystemComponent'
      if ($null -ne $systemComponent) { try { if ([int]$systemComponent -eq 1) { [void]$script:ReportKept.Add("system  $name"); continue } } catch {} }
      if (Test-NameLike $name $protect) { [void]$script:ReportKept.Add("keep    $name"); continue }
    }
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
  try {
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
  } catch {}
  return $removed
}
function Set-NoTaskbar {
  $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
  New-Item -Path $path -Force | Out-Null
  foreach ($pair in @{ NoTrayItemsDisplay = 1; HideClock = 1; HideSCAHealth = 1; HideSCAMeetNow = 1; HideSCANetwork = 1; HideSCAVolume = 1; HideSCAPower = 1; NoAutoTrayNotify = 1; NoSetTaskbar = 1; NoTrayContextMenu = 1 }.GetEnumerator()) {
    try { New-ItemProperty -Path $path -Name $pair.Key -Value $pair.Value -PropertyType DWord -Force | Out-Null } catch {}
  }
  $installed = Install-Self
  try {
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'AdminSetupHideTaskbar' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'AdminSetupFolderLogo' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'AdminSetupStartLogo' -ErrorAction SilentlyContinue
  } catch {}
  Start-Mode $installed 'HideBar' 'AdminSetupHideTaskbar'
  Start-Mode $installed 'Badges' 'AdminSetupFolderLogo' -Sta
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
  $text = ($lines -join [Environment]::NewLine)
  try { $text | Set-Content -Path (Join-Path $homeRoot 'Admin-Setup-last.txt') -Encoding UTF8 } catch {}
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

$doWipe = ($Mode -in @('All','Wipe')) -and -not $SkipWipe
$doTray = ($Mode -in @('All','Wipe')) -and -not $SkipTray
if ($Mode -eq 'Wipe' -and $SkipTray) { $doTray = $false }
$win32 = 0; $store = 0
if ($doWipe) { $win32 = Invoke-ClearWin32Apps; $store = Invoke-ClearStoreApps }
if ($doTray) { Set-NoTaskbar }
Write-Log "Finished Win32=$win32 Store=$store"
Show-WipeReport
