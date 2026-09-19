<#
.SYNOPSIS
  Wipe other drives, then C: (keep Windows), delete all C:\Users folders, Recycle last.
  After wipe, offer Developers Preference package (latest Chrome, Grok, Snipping Tool).
  -ConfirmPhrase WIPE-ALL-DATA   -Mode Wipe to skip badges
#>
[CmdletBinding()]
param(
  [ValidateSet('All','HideBar','Badges','Wipe')]
  [string]$Mode = 'Wipe',
  [string]$ConfirmPhrase = ''
)
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'
$script:AdminDir = Join-Path $env:USERPROFILE 'admin'
$script:Live = ($ConfirmPhrase -eq 'WIPE-ALL-DATA')
$script:Done = 0; $script:Total = 1; $script:T0 = Get-Date
$script:Bar = $null; $script:Lbl = $null; $script:Eta = $null; $script:Win = $null
function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function L([string]$m) {
  New-Item -ItemType Directory -Force -Path $script:AdminDir | Out-Null
  $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $m
  Add-Content (Join-Path $script:AdminDir 'Admin-Setup.log') $line
  Write-Host $line
}
function Is-Blocked([string]$Name) {
  $n = "$Name".ToLowerInvariant()
  return @('system volume information','$recycle.bin','pagefile.sys','hiberfil.sys','swapfile.sys','windows','boot','bootmgr','recovery','$winreagent') -contains $n
}
function Show-Bar {
  Add-Type -AssemblyName System.Windows.Forms, System.Drawing
  $w = New-Object System.Windows.Forms.Form
  $w.Text = 'Wipe'; $w.Size = New-Object System.Drawing.Size(640,150); $w.StartPosition='CenterScreen'; $w.TopMost=$true
  $l = New-Object System.Windows.Forms.Label; $l.SetBounds(12,10,600,36)
  $e = New-Object System.Windows.Forms.Label; $e.SetBounds(12,48,600,20)
  $p = New-Object System.Windows.Forms.ProgressBar; $p.SetBounds(12,74,600,24); $p.Maximum=100
  $w.Controls.AddRange(@($l,$e,$p)); $w.Show(); $w.Refresh()
  $script:Win=$w; $script:Lbl=$l; $script:Eta=$e; $script:Bar=$p
}
function Tick([string]$Path) {
  $script:Done++
  $pct = [Math]::Min(100,[int](100.0 * $script:Done / [Math]::Max(1,$script:Total)))
  $el = ((Get-Date)-$script:T0).TotalSeconds
  $rem = 0
  if ($script:Done -gt 0) { $rem = ($el / $script:Done) * ($script:Total - $script:Done) }
  $msg = '{0}/{1} {2}% {3}' -f $script:Done,$script:Total,$pct,$Path
  Write-Host $msg
  if ($script:Lbl) { $script:Lbl.Text = $msg }
  if ($script:Eta) { $script:Eta.Text = ('elapsed {0:n0}s   eta {1:n0}s' -f $el,[Math]::Max(0,$rem)) }
  if ($script:Bar) { $script:Bar.Value = $pct }
  if ($script:Win) { $script:Win.Refresh(); [System.Windows.Forms.Application]::DoEvents() }
}
function Kill-Fast([string]$Path) {
  $leaf = [IO.Path]::GetFileName($Path)
  if (Is-Blocked $leaf) { L "SKIP $Path"; Tick "SKIP $leaf"; return }
  L "DELETE $Path"
  if ($script:Live) {
    try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop } catch {
      cmd /c "rd /s /q `"$Path`""
      cmd /c "del /f /q `"$Path`""
    }
  }
  if (Test-Path -LiteralPath $Path) { L "LEFT $Path" } else { L "GONE $Path" }
  Tick $Path
}
function List-Kids([string]$Root) {
  $out = @()
  if (-not (Test-Path -LiteralPath $Root)) { return $out }
  cmd /c "dir /a /b `"$Root`"" | ForEach-Object {
    if ($_ -and -not (Is-Blocked $_)) { $out += (Join-Path $Root $_) }
  }
  return $out
}
function Invoke-Wipe {
  $os = $env:SystemDrive.TrimEnd(':')
  $jobs = @()
  Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -in 2,3 } | ForEach-Object {
    $let = $_.DeviceID.TrimEnd(':')
    if ($let -eq $os) { return }
    $jobs += List-Kids ($let + ':\')
  }
  $jobs += List-Kids ($os + ':\') | Where-Object { [IO.Path]::GetFileName($_).ToLowerInvariant() -ne 'users' }
  $jobs += List-Kids ($os + ':\Users')
  $script:Total = [Math]::Max(1, $jobs.Count)
  $script:Done = 0; $script:T0 = Get-Date
  Show-Bar
  L "jobs=$($script:Total) live=$($script:Live)"
  $osRoot = ($os + ':\').ToLowerInvariant()
  foreach ($p in $jobs) { if (-not $p.ToLowerInvariant().StartsWith($osRoot)) { Kill-Fast $p } }
  foreach ($p in $jobs) { if ($p.ToLowerInvariant().StartsWith($osRoot)) { Kill-Fast $p } }
  if ($script:Live) { try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {} }
  if ($script:Bar) { $script:Bar.Value = 100 }
  if ($script:Win) { Start-Sleep 1; $script:Win.Close() }
  L 'WIPE DONE'
}
function Start-HideBar {
  $m = New-Object System.Threading.Mutex($false, 'Local\AdminSetupHideTaskbar')
  if (-not $m.WaitOne(0,$false)) { return }
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
  if (-not $m.WaitOne(0,$false)) { return }
  Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase, System.Drawing
  $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" WindowStyle="None" AllowsTransparency="True" Background="Transparent" ShowInTaskbar="False" Topmost="True" ResizeMode="NoResize" SizeToContent="WidthAndHeight">
  <StackPanel Orientation="Horizontal" Margin="8">
    <Grid Width="64" Height="64" Margin="0,0,18,0" Cursor="Hand" Name="BtnFolder"><Ellipse Fill="#FF2A2A2A" Stroke="#FFE6B422" StrokeThickness="2"/></Grid>
    <Grid Width="64" Height="64" Cursor="Hand" Name="BtnPs"><Ellipse Fill="#FF172233" Stroke="#FF3B9AE1" StrokeThickness="2"/></Grid>
  </StackPanel>
</Window>
'@
  $w = [Windows.Markup.XamlReader]::Parse($xaml)
  $w.FindName('BtnFolder').Add_MouseLeftButtonUp({ Start-Process explorer.exe $env:USERPROFILE | Out-Null })
  $w.FindName('BtnPs').Add_MouseLeftButtonUp({ Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" | Out-Null })
  $w.Add_ContentRendered({ $w.Left = ([System.Windows.SystemParameters]::PrimaryScreenWidth - $w.ActualWidth)/2; $w.Top = [System.Windows.SystemParameters]::PrimaryScreenHeight - $w.ActualHeight - 16 })
  [void]$w.ShowDialog()
}
function Try-Winget([string]$Id) {
  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if (-not $winget) { return $false }
  L "WINGET $Id"
  & winget install -e --id $Id --accept-package-agreements --accept-source-agreements --disable-interactivity
  return ($LASTEXITCODE -eq 0)
}
function Install-LatestChrome {
  if (Try-Winget 'Google.Chrome') { L 'CHROME winget ok'; return }
  $ProgressPreference = 'SilentlyContinue'
  $dir = Join-Path $env:USERPROFILE 'Downloads'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $msi = Join-Path $dir 'Chrome64.msi'
  L 'CHROME fetch standalone enterprise 64'
  Invoke-WebRequest 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi' -OutFile $msi -UseBasicParsing
  Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn" -Wait
  L 'CHROME msi done'
}
function Install-GrokBot {
  if (Try-Winget 'xAI.GrokBuild') { L 'GROK winget ok' } else { L 'GROK winget miss; open grok.com' }
  $chrome = @( 
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
  if ($chrome) { Start-Process $chrome 'https://grok.com' } else { Start-Process 'https://grok.com' }
}
function Install-SnippingTool {
  if (Try-Winget '9MZ95KL8MR0L') { L 'SNIP winget ok' } else { L 'SNIP winget miss' }
  foreach ($exe in @(
    "$env:SystemRoot\System32\SnippingTool.exe",
    "$env:SystemRoot\System32\ScreenSketch.exe"
  )) {
    if (Test-Path $exe) { Start-Process $exe; return }
  }
  try { Start-Process 'ms-screenclip:' } catch { Start-Process 'snippingtool.exe' }
}
function Offer-DevPref {
  Add-Type -AssemblyName System.Windows.Forms
  $r = [System.Windows.Forms.MessageBox]::Show(
    'Install Developers Preference package?' + [Environment]::NewLine + [Environment]::NewLine +
    'Latest Chrome, Grok, and Snipping Tool.',
    'Developers Preference',
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question
  )
  if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { L 'DEVPREF declined'; return }
  L 'DEVPREF yes'
  Install-LatestChrome
  Install-GrokBot
  Install-SnippingTool
  L 'DEVPREF done'
}
if ($Mode -eq 'HideBar') { Start-HideBar; return }
if ($Mode -eq 'Badges') { Start-Badges; return }
if (-not (Test-Admin)) {
  $self = $PSCommandPath
  if (-not $self) { $self = Join-Path $script:AdminDir 'Admin-Setup.ps1' }
  Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$self`" -Mode $Mode -ConfirmPhrase $ConfirmPhrase"
  return
}
Invoke-Wipe
Offer-DevPref
L 'DONE'
