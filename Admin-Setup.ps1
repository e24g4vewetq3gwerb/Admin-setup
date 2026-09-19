<#
.SYNOPSIS
  Wipe apps except Terminal and File Explorer. Hide taskbar. Three badges.
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
function Test-KeepEssential([string]$Name) {
  return (Test-NameLike $Name @(
    'Windows Terminal*','Microsoft.WindowsTerminal*','*WindowsTerminal*',
    '*FileExp*','*File Explorer*','*Explorer++*','Microsoft Windows Explorer*'
  ))
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
  $folderImg = Get-ExeImage (Join-Path $env:SystemRoot 'explorer.exe')
  $psImg = Get-ExeImage (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
  $selfPath = Get-SelfPath
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
  $window.FindName('ImgFolder').Source = $folderImg
  $window.FindName('ImgPs').Source = $psImg
  function Move-ToBottom {
    $sw = [System.Windows.SystemParameters]::PrimaryScreenWidth
    $sh = [System.Windows.SystemParameters]::PrimaryScreenHeight
    $window.Left = [Math]::Max(0, ($sw - $window.ActualWidth) / 2)
    $window.Top = $sh - $window.ActualHeight - 16
  }
  function Confirm-AndRun {
    $target = Join-Path $env:USERPROFILE 'admin\Admin-Setup.ps1'
    if (-not (Test-Path -LiteralPath $target)) { $target = $selfPath }
    if (-not $target) { return }
    $answer = [System.Windows.MessageBox]::Show('Wipe again? Keeps Terminal and File Explorer. Continue?', 'Confirm wipe', 'YesNo', 'Exclamation', 'No')
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList @('-STA','-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$target`"",'-Mode','Wipe') | Out-Null
  }
  $window.FindName('BtnFolder').Add_MouseLeftButtonUp({ Start-Process explorer.exe $env:USERPROFILE | Out-Null })
  $window.FindName('BtnPs').Add_MouseLeftButtonUp({ Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" | Out-Null })
  $window.FindName('BtnScript').Add_MouseLeftButtonUp({ Confirm-AndRun })
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
$log = Join-Path $homeRoot 'Admin-Setup.log'
$reportFile = Join-Path $homeRoot 'Admin-Setup-last.txt'
$script:ReportKept = New-Object System.Collections.Generic.List[string]
$script:ReportCleared = New-Object System.Collections.Generic.List[string]
$script:ReportFailed = New-Object System.Collections.Generic.List[string]
$script:ReportLeft = New-Object System.Collections.Generic.List[string]
$script:ReportFound = 0
function Write-Log([string]$Message) {
  $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message
  try { Add-Content -Path $log -Value $line } catch {}
  Write-Host $line
}

Write-Log 'Admin-Setup start'

if (-not (Test-IsAdmin)) {
  Write-Log 'Not admin - requesting UAC. Approve the prompt. Report opens after wipe.'
  $self = Get-SelfPath
  if (-not $self) { $self = $MyInvocation.MyCommand.Definition }
  $arg = @('-STA','-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$self`"",'-Mode',$Mode)
  if ($SkipWipe) { $arg += '-SkipWipe' }
  if ($SkipTray) { $arg += '-SkipTray' }
  Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -Wait -ArgumentList $arg | Out-Null
  if (Test-Path -LiteralPath $reportFile) {
    Write-Host ''
    Write-Host '===== REPORT ====='
    Get-Content -LiteralPath $reportFile | Write-Host
    notepad.exe $reportFile
  } else {
    Write-Log 'No report file. UAC may have been cancelled.'
  }
  return
}

Write-Log 'Admin OK - scanning and wiping'

function Install-Self {
  $self = Get-SelfPath
  $dest = Join-Path $homeRoot 'Admin-Setup.ps1'
  if ($self -and (Test-Path -LiteralPath $self) -and ([IO.Path]::GetFullPath($self) -ne [IO.Path]::GetFullPath($dest))) {
    Copy-Item -LiteralPath $self -Destination $dest -Force
  }
  if (Test-Path -LiteralPath $dest) { Copy-Item -LiteralPath $dest -Destination (Join-Path $homeRoot 'Clear-Apps-And-Tray.ps1') -Force }
  return $dest
}
function Start-Mode([string]$Path, [string]$HelperMode, [string]$RunName, [switch]$Sta) {
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
  New-Item -Path $runKey -Force | Out-Null
  $staBit = if ($Sta) { '-STA ' } else { '' }
  $cmd = "`"$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe`" $staBit-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Path`" -Mode $HelperMode"
  New-ItemProperty -Path $runKey -Name $RunName -Value $cmd.Trim() -PropertyType String -Force | Out-Null
  $a = @('-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',"`"$Path`"",'-Mode',$HelperMode)
  if ($Sta) { $a = @('-STA') + $a }
  Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -WindowStyle Hidden -ArgumentList $a | Out-Null
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
    if (("$args").ToLowerInvariant() -notmatch '/s\b|/silent|/quiet|/qn|/norestart') { $args = ("$args /S /silent /quiet /norestart").Trim() }
    $p = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
    return ($null -eq $p.ExitCode -or $p.ExitCode -in 0, 1, 1605, 1614, 1641, 3010)
  } catch { return $false }
}
function Invoke-ClearWin32Apps {
  Write-Log 'Win32 uninstall list...'
  $paths = @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')
  $removed = 0
  foreach ($prog in @(Get-ItemProperty $paths -ErrorAction SilentlyContinue)) {
    $name = [string](Get-Prop $prog 'DisplayName')
    if (-not $name) { continue }
    $script:ReportFound++
    if (Test-KeepEssential $name) { [void]$script:ReportKept.Add($name); continue }
    $uninstall = [string](Get-Prop $prog 'QuietUninstallString')
    if (-not $uninstall) { $uninstall = [string](Get-Prop $prog 'UninstallString') }
    if (-not $uninstall) { [void]$script:ReportFailed.Add($name); continue }
    Write-Log "Uninstall $name"
    if (Invoke-UninstallCommand $uninstall) { $removed++; [void]$script:ReportCleared.Add($name) } else { [void]$script:ReportFailed.Add($name) }
  }
  return $removed
}
function Invoke-ClearStoreApps {
  Write-Log 'Store package list...'
  $removed = 0
  foreach ($pkg in @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)) {
    $name = [string]$pkg.Name
    if (-not $name) { continue }
    $script:ReportFound++
    if (Test-KeepEssential $name) { [void]$script:ReportKept.Add("Store: $name"); continue }
    Write-Log "Remove Store $name"
    $ok = $false
    try { Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop; $ok = $true } catch {
      try { Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop; $ok = $true } catch {}
    }
    if ($ok) { $removed++; [void]$script:ReportCleared.Add("Store: $name") } else { [void]$script:ReportFailed.Add("Store: $name") }
  }
  return $removed
}
function Get-StillInstalled {
  Write-Log 'Rescan leftovers...'
  $seen = @{}
  $paths = @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')
  foreach ($prog in @(Get-ItemProperty $paths -ErrorAction SilentlyContinue)) {
    $name = [string](Get-Prop $prog 'DisplayName')
    if (-not $name) { continue }
    $tag = if (Test-KeepEssential $name) { 'KEEP  ' } else { 'LEFT  ' }
    $key = "w:$name"
    if (-not $seen.ContainsKey($key)) { $seen[$key] = $true; [void]$script:ReportLeft.Add("$tag$name") }
  }
  foreach ($pkg in @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)) {
    $name = [string]$pkg.Name
    if (-not $name) { continue }
    $tag = if (Test-KeepEssential $name) { 'KEEP  Store: ' } else { 'LEFT  Store: ' }
    $key = "s:$name"
    if (-not $seen.ContainsKey($key)) { $seen[$key] = $true; [void]$script:ReportLeft.Add("$tag$name") }
  }
}
function Set-NoTaskbar {
  Write-Log 'Hide taskbar + badges'
  $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
  New-Item -Path $path -Force | Out-Null
  foreach ($pair in @{ NoTrayItemsDisplay = 1; HideClock = 1; HideSCAHealth = 1; HideSCAMeetNow = 1; HideSCANetwork = 1; HideSCAVolume = 1; HideSCAPower = 1; NoAutoTrayNotify = 1; NoSetTaskbar = 1; NoTrayContextMenu = 1 }.GetEnumerator()) {
    try { New-ItemProperty -Path $path -Name $pair.Key -Value $pair.Value -PropertyType DWord -Force | Out-Null } catch {}
  }
  $installed = Install-Self
  Start-Mode $installed 'HideBar' 'AdminSetupHideTaskbar'
  Start-Mode $installed 'Badges' 'AdminSetupFolderLogo' -Sta
}
function Write-ReportText {
  $keepNow = @($script:ReportLeft | Where-Object { $_ -like 'KEEP *' })
  $leftNow = @($script:ReportLeft | Where-Object { $_ -like 'LEFT *' })
  $lines = New-Object System.Collections.Generic.List[string]
  [void]$lines.Add('======== SUMMARY ========')
  [void]$lines.Add((Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
  [void]$lines.Add("PC  $env:COMPUTERNAME   user  $env:USERNAME")
  [void]$lines.Add('')
  [void]$lines.Add("Found     $($script:ReportFound)")
  [void]$lines.Add("Cleared   $($script:ReportCleared.Count)")
  [void]$lines.Add("Failed    $($script:ReportFailed.Count)")
  [void]$lines.Add("KEEP now  $($keepNow.Count)")
  [void]$lines.Add("LEFT now  $($leftNow.Count)")
  [void]$lines.Add('')
  [void]$lines.Add('--- KEEP (Terminal / File Explorer) ---')
  if ($keepNow.Count -eq 0) { [void]$lines.Add('(none)') } else { $keepNow | Sort-Object | ForEach-Object { [void]$lines.Add($_) } }
  [void]$lines.Add('')
  [void]$lines.Add('--- LEFT (still installed, Windows blocked or no uninstaller) ---')
  if ($leftNow.Count -eq 0) { [void]$lines.Add('(none)') } else { $leftNow | Sort-Object | ForEach-Object { [void]$lines.Add($_) } }
  [void]$lines.Add('')
  [void]$lines.Add('--- CLEARED this run ---')
  if ($script:ReportCleared.Count -eq 0) { [void]$lines.Add('(none)') } else { $script:ReportCleared | Sort-Object | ForEach-Object { [void]$lines.Add($_) } }
  [void]$lines.Add('')
  [void]$lines.Add('--- FAILED this run ---')
  if ($script:ReportFailed.Count -eq 0) { [void]$lines.Add('(none)') } else { $script:ReportFailed | Sort-Object | ForEach-Object { [void]$lines.Add($_) } }
  $text = $lines -join [Environment]::NewLine
  Set-Content -Path $reportFile -Value $text -Encoding UTF8
  Write-Host $text
  return $text
}
function Show-WipeReport {
  $text = Write-ReportText
  try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $win = New-Object System.Windows.Forms.Form
    $win.Text = 'Admin Setup - SUMMARY'
    $win.Size = New-Object System.Drawing.Size(780, 620)
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
  } catch {
    Write-Log "Dialog failed: $($_.Exception.Message)"
    try { notepad.exe $reportFile } catch {}
  }
}

try {
  $doWipe = ($Mode -in @('All','Wipe')) -and -not $SkipWipe
  $doTray = ($Mode -in @('All','Wipe')) -and -not $SkipTray
  if ($doWipe) {
    [void](Invoke-ClearWin32Apps)
    [void](Invoke-ClearStoreApps)
  }
  if ($doTray) { Set-NoTaskbar }
  Get-StillInstalled
  Write-Log 'Writing summary'
  Show-WipeReport
  Write-Log "Done. Report file: $reportFile"
} catch {
  Write-Log "CRASH: $($_.Exception.Message)"
  try { Set-Content -Path $reportFile -Value "CRASH $($_.Exception.Message)" } catch {}
  try { notepad.exe $reportFile } catch {}
}
