<#
.SYNOPSIS
  Launch badges. After wipe confirm, optional Grok Bot + Chrome badges.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'

$mutex = New-Object System.Threading.Mutex($false, 'Local\AdminSetupFolderLogo')
if (-not $mutex.WaitOne(0, $false)) { return }

Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase, System.Drawing

$flagKey = 'HKCU:\Software\AdminSetup'
$flagName = 'DevPackage'
$scriptPath = Join-Path $env:USERPROFILE 'admin\Clear-Apps-And-Tray.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) {
  $alt = Join-Path (Split-Path -Parent $PSCommandPath) 'Clear-Apps-And-Tray.ps1'
  if (Test-Path -LiteralPath $alt) { $scriptPath = $alt }
}

function Get-DevPackageEnabled {
  try {
    $v = Get-ItemProperty -Path $flagKey -Name $flagName -ErrorAction Stop
    return [int]$v.$flagName -eq 1
  } catch { return $false }
}
function Set-DevPackageEnabled([bool]$On) {
  New-Item -Path $flagKey -Force | Out-Null
  New-ItemProperty -Path $flagKey -Name $flagName -Value ($(if ($On) { 1 } else { 0 })) -PropertyType DWord -Force | Out-Null
}

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
  if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
  try {
    $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($Path)
    if ($ico) { return Convert-ToBitmapSource $ico.ToBitmap() }
  } catch {}
  return $null
}
function Find-Chrome {
  @(.
    "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
  ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
function Find-Grok {
  $hits = @()
  foreach ($root in @(
    $env:LOCALAPPDATA,
    $env:ProgramFiles,
    ${env:ProgramFiles(x86)},
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs')
  )) {
    if (-not $root -or -not (Test-Path $root)) { continue }
    $hits += Get-ChildItem -LiteralPath $root -Recurse -ErrorAction SilentlyContinue -Include 'Grok*.exe','Grok Bot.exe','Grok.exe' |
      Where-Object { $_.FullName -notmatch '\\Windows\\' } |
      Select-Object -First 3
  }
  $exe = $hits | Where-Object { $_.Extension -eq '.exe' } | Select-Object -First 1
  if ($exe) { return $exe.FullName }
  $lnk = Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs" -Recurse -Filter '*Grok*.lnk' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($lnk) { return $lnk.FullName }
  return $null
}

$folderImg = Get-ExeImage (Join-Path $env:SystemRoot 'explorer.exe')
$psImg = Get-ExeImage (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
$chromePath = Find-Chrome
$grokPath = Find-Grok
$chromeImg = Get-ExeImage $chromePath
$grokImg = Get-ExeImage $grokPath

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Launch" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ShowInTaskbar="False" Topmost="True"
        ResizeMode="NoResize" SizeToContent="WidthAndHeight"
        UseLayoutRounding="True" SnapsToDevicePixels="True">
  <StackPanel Name="Row" Orientation="Horizontal" Margin="8,8,8,10">
    <Grid Width="64" Height="64" Margin="0,0,18,0" Cursor="Hand" Name="BtnFolder" ToolTip="Open your folder">
      <Ellipse Fill="#FF2A2A2A" Stroke="#FFE6B422" StrokeThickness="2.2"/>
      <Image Name="ImgFolder" Width="30" Height="30" RenderOptions.BitmapScalingMode="HighQuality"/>
    </Grid>
    <Grid Width="64" Height="64" Margin="0,0,18,0" Cursor="Hand" Name="BtnPs" ToolTip="Open PowerShell">
      <Ellipse Fill="#FF172233" Stroke="#FF3B9AE1" StrokeThickness="2.2"/>
      <Image Name="ImgPs" Width="30" Height="30" RenderOptions.BitmapScalingMode="HighQuality"/>
    </Grid>
    <Grid Width="64" Height="64" Margin="0,0,18,0" Cursor="Hand" Name="BtnScript" ToolTip="Clear apps (asks first)">
      <Ellipse Fill="#FF14301F" Stroke="#FF3DDC84" StrokeThickness="2.2"/>
      <Viewbox Width="28" Height="28">
        <Canvas Width="48" Height="48">
          <Path Fill="#FF3DDC84" Data="M 14,14 L 34,14 L 32,40 L 16,40 Z"/>
          <Path Fill="#FF3DDC84" Data="M 10,10 L 38,10 L 38,14 L 10,14 Z"/>
          <Path Fill="#FF3DDC84" Data="M 18,6 L 30,6 L 32,10 L 16,10 Z"/>
        </Canvas>
      </Viewbox>
    </Grid>
    <Grid Width="64" Height="64" Margin="0,0,18,0" Cursor="Hand" Name="BtnChrome" ToolTip="Google Chrome" Visibility="Collapsed">
      <Ellipse Fill="#FF2A1210" Stroke="#FFEA4335" StrokeThickness="2.2"/>
      <Image Name="ImgChrome" Width="30" Height="30" RenderOptions.BitmapScalingMode="HighQuality"/>
      <TextBlock Name="TxtChrome" Text="C" Foreground="#FFEA4335" FontSize="22" FontWeight="Bold"
                 HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"/>
    </Grid>
    <Grid Width="64" Height="64" Cursor="Hand" Name="BtnGrok" ToolTip="Grok Bot" Visibility="Collapsed">
      <Ellipse Fill="#FF1A1A1A" Stroke="#FFE8E8E8" StrokeThickness="2.2"/>
      <Image Name="ImgGrok" Width="30" Height="30" RenderOptions.BitmapScalingMode="HighQuality"/>
      <TextBlock Name="TxtGrok" Text="G" Foreground="White" FontSize="22" FontWeight="Bold"
                 HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"/>
    </Grid>
  </StackPanel>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Parse($xaml)
$window.FindName('ImgFolder').Source = $folderImg
$window.FindName('ImgPs').Source = $psImg
if ($chromeImg) { $window.FindName('ImgChrome').Source = $chromeImg } else { $window.FindName('TxtChrome').Visibility = 'Visible' }
if ($grokImg) { $window.FindName('ImgGrok').Source = $grokImg } else { $window.FindName('TxtGrok').Visibility = 'Visible' }

function Set-DevBadgesVisible([bool]$On) {
  $vis = if ($On) { 'Visible' } else { 'Collapsed' }
  $window.FindName('BtnChrome').Visibility = $vis
  $window.FindName('BtnGrok').Visibility = $vis
  $window.UpdateLayout()
  Move-ToBottom
}
function Move-ToBottom {
  $sw = [System.Windows.SystemParameters]::PrimaryScreenWidth
  $sh = [System.Windows.SystemParameters]::PrimaryScreenHeight
  $window.Left = [Math]::Max(0, ($sw - $window.ActualWidth) / 2)
  $window.Top = $sh - $window.ActualHeight - 16
}

function Confirm-AndRun {
  if (-not (Test-Path -LiteralPath $scriptPath)) {
    [System.Windows.MessageBox]::Show("Script not found:`n$scriptPath", 'Admin Setup', 'OK', 'Warning') | Out-Null
    return
  }
  $wipe = [System.Windows.MessageBox]::Show(
    "Run Clear Apps and Tray again?`n`nThis uninstalls removable programs and keeps the taskbar hidden.`nA report opens when it finishes.`n`nContinue?",
    'Confirm wipe', 'YesNo', 'Exclamation', 'No')
  if ($wipe -ne [System.Windows.MessageBoxResult]::Yes) { return }

  $pkg = [System.Windows.MessageBox]::Show(
    "Add the developer preferred package?`n`nGrok Bot and Google Chrome shortcuts will appear beside this wipe button.",
    'Developer package', 'YesNo', 'Question', 'No')
  if ($pkg -eq [System.Windows.MessageBoxResult]::Yes) {
    Set-DevPackageEnabled $true
    Set-DevBadgesVisible $true
  }

  $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  Start-Process -FilePath $ps -Verb RunAs -ArgumentList @(
    '-STA','-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$scriptPath`"",'-ShowReport'
  ) | Out-Null
}

function Open-Chrome {
  $exe = Find-Chrome
  if ($exe) { Start-Process $exe | Out-Null; return }
  Start-Process 'https://www.google.com/chrome/' | Out-Null
}
function Open-Grok {
  $exe = Find-Grok
  if ($exe) { Start-Process $exe | Out-Null; return }
  Start-Process 'https://grok.com/' | Out-Null
}

$window.FindName('BtnFolder').Add_MouseLeftButtonUp({
  Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList @("`"$env:USERPROFILE`"") | Out-Null
})
$window.FindName('BtnPs').Add_MouseLeftButtonUp({
  Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') | Out-Null
})
$window.FindName('BtnScript').Add_MouseLeftButtonUp({ Confirm-AndRun })
$window.FindName('BtnChrome').Add_MouseLeftButtonUp({ Open-Chrome })
$window.FindName('BtnGrok').Add_MouseLeftButtonUp({ Open-Grok })

Set-DevBadgesVisible (Get-DevPackageEnabled)
$window.Add_ContentRendered({ Move-ToBottom })
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(3)
$timer.Add_Tick({ $window.Topmost = $true; Move-ToBottom })
$timer.Start()
[void]$window.ShowDialog()
