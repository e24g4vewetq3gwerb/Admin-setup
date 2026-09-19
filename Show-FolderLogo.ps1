<#
.SYNOPSIS
  HD circular launch badges: folder, PowerShell, wipe (with confirm).
#>
[CmdletBinding()]
param()
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'

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
$scriptPath = Join-Path $env:USERPROFILE 'admin\Clear-Apps-And-Tray.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) {
  $alt = Join-Path (Split-Path -Parent $PSCommandPath) 'Clear-Apps-And-Tray.ps1'
  if (Test-Path -LiteralPath $alt) { $scriptPath = $alt }
}

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
  if (-not (Test-Path -LiteralPath $scriptPath)) {
    [System.Windows.MessageBox]::Show("Script not found:`n$scriptPath", 'Admin Setup', 'OK', 'Warning') | Out-Null
    return
  }
  $msg = "Run Clear Apps and Tray again?`n`nThis will uninstall removable programs and keep the taskbar hidden.`nA report opens when it finishes.`n`nContinue?"
  $answer = [System.Windows.MessageBox]::Show($msg, 'Confirm wipe', 'YesNo', 'Exclamation', 'No')
  if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
  $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  Start-Process -FilePath $ps -Verb RunAs -ArgumentList @(
    '-STA','-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$scriptPath`"",'-ShowReport'
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
