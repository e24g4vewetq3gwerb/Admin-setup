<#
.SYNOPSIS
  HD circular launch badges (WPF): folder, PowerShell, wipe script.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version 1
$ErrorActionPreference = 'Continue'

$mutex = New-Object System.Threading.Mutex($false, 'Local\AdminSetupFolderLogo')
if (-not $mutex.WaitOne(0, $false)) { return }

Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase, System.Drawing, System.Windows.Forms

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
  <Window.Resources>
    <Style TargetType="Ellipse" x:Key="Ring">
      <Setter Property="Width" Value="64"/>
      <Setter Property="Height" Value="64"/>
      <Setter Property="StrokeThickness" Value="2.2"/>
    </Style>
  </Window.Resources>
  <StackPanel Orientation="Horizontal" Margin="8,8,8,10">
    <Grid Width="64" Height="64" Margin="0,0,18,0" Cursor="Hand" Name="BtnFolder">
      <Ellipse Fill="#FF2A2A2A" Stroke="#FFE6B422" Style="{StaticResource Ring}"/>
      <Image Name="ImgFolder" Width="30" Height="30" RenderOptions.BitmapScalingMode="HighQuality"/>
    </Grid>
    <Grid Width="64" Height="64" Margin="0,0,18,0" Cursor="Hand" Name="BtnPs">
      <Ellipse Fill="#FF172233" Stroke="#FF3B9AE1" Style="{StaticResource Ring}"/>
      <Image Name="ImgPs" Width="30" Height="30" RenderOptions.BitmapScalingMode="HighQuality"/>
    </Grid>
    <Grid Width="64" Height="64" Cursor="Hand" Name="BtnScript">
      <Ellipse Fill="#FF14301F" Stroke="#FF3DDC84" Style="{StaticResource Ring}"/>
      <Viewbox Width="30" Height="30">
        <Canvas Width="48" Height="48">
          <Path Stroke="#FF3DDC84" StrokeThickness="3.4" StrokeStartLineCap="Round" StrokeEndLineCap="Round"
                Data="M 10,18 A 14,14 0 1 1 16,36" Fill="Transparent"/>
          <Path Fill="#FF3DDC84" Data="M 8,12 L 18,18 L 8,22 Z"/>
          <Path Stroke="#FF3DDC84" StrokeThickness="3.4" StrokeStartLineCap="Round" StrokeEndLineCap="Round"
                Data="M 38,30 A 14,14 0 1 1 32,12" Fill="Transparent"/>
          <Path Fill="#FF3DDC84" Data="M 40,36 L 30,30 L 40,26 Z"/>
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
  $wa = [System.Windows.SystemParameters]::WorkArea
  if ($wa.Height -lt 100) { $wa = [System.Windows.SystemParameters]::PrimaryScreenHeight; $sw = [System.Windows.SystemParameters]::PrimaryScreenWidth }
  $sw = [System.Windows.SystemParameters]::PrimaryScreenWidth
  $sh = [System.Windows.SystemParameters]::PrimaryScreenHeight
  $window.Left = [Math]::Max(0, ($sw - $window.ActualWidth) / 2)
  $window.Top = $sh - $window.ActualHeight - 16
}

$window.FindName('BtnFolder').Add_MouseLeftButtonUp({
  Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList @("`"$env:USERPROFILE`"") | Out-Null
})
$window.FindName('BtnPs').Add_MouseLeftButtonUp({
  Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') | Out-Null
})
$window.FindName('BtnScript').Add_MouseLeftButtonUp({
  if (-not (Test-Path -LiteralPath $scriptPath)) { return }
  $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  Start-Process -FilePath $ps -Verb RunAs -ArgumentList @(
    '-STA','-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$scriptPath`"",'-ShowReport'
  ) | Out-Null
})

$window.Add_ContentRendered({ Move-ToBottom })
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(3)
$timer.Add_Tick({ $window.Topmost = $true; Move-ToBottom })
$timer.Start()

[void]$window.ShowDialog()
