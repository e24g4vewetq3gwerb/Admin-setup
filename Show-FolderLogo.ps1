<#
.SYNOPSIS
  Badges: folder, PowerShell, wipe, Chrome, Grok Bot.
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
  if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
  try {
    $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($Path)
    if ($ico) { return Convert-ToBitmapSource $ico.ToBitmap() }
  } catch {}
  return $null
}
function Find-Chrome {
  @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
  ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
}
function Find-Grok {
  $names = @('Grok Bot.exe','GrokBot.exe','Grok.exe')
  $roots = @(
    "$env:LOCALAPPDATA\Programs",
    "$env:LOCALAPPDATA",
    $env:ProgramFiles,
    ${env:ProgramFiles(x86)}
  )
  foreach ($root in $roots) {
    if (-not $root -or -not (Test-Path $root)) { continue }
    foreach ($n in $names) {
      $hit = Get-ChildItem -LiteralPath $root -Filter $n -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($hit) { return $hit.FullName }
    }
  }
  $lnk = Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs" -Recurse -Filter '*Grok*.lnk' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($lnk) { return $lnk.FullName }
  return $null
}

$scriptPath = Join-Path $env:USERPROFILE 'admin\Clear-Apps-And-Tray.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) {
  $alt = Join-Path (Split-Path -Parent $PSCommandPath) 'Clear-Apps-And-Tray.ps1'
  if (Test-Path -LiteralPath $alt) { $scriptPath = $alt }
}

$folderImg = Get-ExeImage (Join-Path $env:SystemRoot 'explorer.exe')
$psImg = Get-ExeImage (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
$chromeImg = Get-ExeImage (Find-Chrome)
$grokImg = Get-ExeImage (Find-Grok)

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Launch" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ShowInTaskbar="False" Topmost="True"
        ResizeMode="NoResize" SizeToContent="WidthAndHeight"
        UseLayoutRounding="True" SnapsToDevicePixels="True">
  <StackPanel Orientation="Horizontal" Margin="8,8,8,10">
    <Grid Width="64" Height="64" Margin="0,0,16,0" Cursor="Hand" Name="BtnFolder" ToolTip="Folder">
      <Ellipse Fill="#FF2A2A2A" Stroke="#FFE6B422" StrokeThickness="2.2"/>
      <Image Name="ImgFolder" Width="30" Height="30" RenderOptions.BitmapScalingMode="HighQuality"/>
    </Grid>
    <Grid Width="64" Height="64" Margin="0,0,16,0" Cursor="Hand" Name="BtnPs" ToolTip="PowerShell">
      <Ellipse Fill="#FF172233" Stroke="#FF3B9AE1" StrokeThickness="2.2"/>
      <Image Name="ImgPs" Width="30" Height="30" RenderOptions.BitmapScalingMode="HighQuality"/>
    </Grid>
    <Grid Width="64" Height="64" Margin="0,0,16,0" Cursor="Hand" Name="BtnScript" ToolTip="Wipe (asks first)">
      <Ellipse Fill="#FF14301F" Stroke="#FF3DDC84" StrokeThickness="2.2"/>
      <Viewbox Width="26" Height="26">
        <Canvas Width="48" Height="48">
          <Path Fill="#FF3DDC84" Data="M 18,8 L 38,24 L 18,40 Z"/>
        </Canvas>
      </Viewbox>
    </Grid>
    <Grid Width="64" Height="64" Margin="0,0,16,0" Cursor="Hand" Name="BtnChrome" ToolTip="Chrome — open or install latest">
      <Ellipse Fill="#FF2A1210" Stroke="#FFEA4335" StrokeThickness="2.2"/>
      <Image Name="ImgChrome" Width="30" Height="30" RenderOptions.BitmapScalingMode="HighQuality"/>
      <TextBlock Name="TxtChrome" Text="C" Foreground="#FFEA4335" FontSize="22" FontWeight="Bold"
                 HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Grid>
    <Grid Width="64" Height="64" Cursor="Hand" Name="BtnGrok" ToolTip="Grok Bot — open or install latest">
      <Ellipse Fill="#FF141414" Stroke="#FFE8E8E8" StrokeThickness="2.2"/>
      <Image Name="ImgGrok" Width="30" Height="30" RenderOptions.BitmapScalingMode="HighQuality"/>
      <TextBlock Name="TxtGrok" Text="G" Foreground="White" FontSize="22" FontWeight="Bold"
                 HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Grid>
  </StackPanel>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Parse($xaml)
$window.FindName('ImgFolder').Source = $folderImg
$window.FindName('ImgPs').Source = $psImg
if ($chromeImg) { $window.FindName('ImgChrome').Source = $chromeImg; $window.FindName('TxtChrome').Visibility = 'Collapsed' }
if ($grokImg) { $window.FindName('ImgGrok').Source = $grokImg; $window.FindName('TxtGrok').Visibility = 'Collapsed' }

function Move-ToBottom {
  $sw = [System.Windows.SystemParameters]::PrimaryScreenWidth
  $sh = [System.Windows.SystemParameters]::PrimaryScreenHeight
  $window.Left = [Math]::Max(0, ($sw - $window.ActualWidth) / 2)
  $window.Top = $sh - $window.ActualHeight - 16
}

function Install-LatestChrome {
  $tmp = Join-Path $env:TEMP 'chrome_installer.exe'
  Invoke-WebRequest -Uri 'https://dl.google.com/chrome/install/latest/chrome_installer.exe' -OutFile $tmp -UseBasicParsing
  Start-Process -FilePath $tmp -ArgumentList '/silent','/install' -Wait
}
function Get-GrokDownloadUrl {
  $arch = $env:PROCESSOR_ARCHITECTURE
  if ($arch -eq 'ARM64') {
    return 'https://api2.cursor.sh/updates/download/stable/win32-arm64/grok-bot'
  }
  return 'https://api2.cursor.sh/updates/download/stable/win32-x64/grok-bot-cf55d121b6d17368'
}
function Install-LatestGrok {
  $tmp = Join-Path $env:TEMP 'GrokBotSetup.exe'
  Invoke-WebRequest -Uri (Get-GrokDownloadUrl) -OutFile $tmp -UseBasicParsing
  Start-Process -FilePath $tmp -Wait
}

function Start-ChromeFlow {
  $exe = Find-Chrome
  if ($exe) { Start-Process $exe | Out-Null; return }
  $q = [System.Windows.MessageBox]::Show('Chrome is not installed. Download and install the latest official Chrome now?','Chrome','YesNo','Question','Yes')
  if ($q -ne [System.Windows.MessageBoxResult]::Yes) { return }
  try {
    Install-LatestChrome
    Start-Sleep 2
    $exe = Find-Chrome
    if ($exe) { Start-Process $exe | Out-Null }
    else { [System.Windows.MessageBox]::Show('Chrome installer finished. Open Chrome from Start if it does not appear.','Chrome','OK','Information') | Out-Null }
  } catch {
    [System.Windows.MessageBox]::Show("Chrome install failed:`n$($_.Exception.Message)",'Chrome','OK','Error') | Out-Null
    Start-Process 'https://www.google.com/chrome/' | Out-Null
  }
}
function Start-GrokFlow {
  $exe = Find-Grok
  if ($exe) { Start-Process $exe | Out-Null; return }
  $q = [System.Windows.MessageBox]::Show('Grok Bot is not installed. Download and install the latest official Windows build now?','Grok Bot','YesNo','Question','Yes')
  if ($q -ne [System.Windows.MessageBoxResult]::Yes) { return }
  try {
    Install-LatestGrok
    Start-Sleep 2
    $exe = Find-Grok
    if ($exe) { Start-Process $exe | Out-Null }
    else { Start-Process 'https://x.ai/bot' | Out-Null }
  } catch {
    [System.Windows.MessageBox]::Show("Grok Bot install failed:`n$($_.Exception.Message)`nOpening the download page.",'Grok Bot','OK','Error') | Out-Null
    Start-Process 'https://x.ai/bot' | Out-Null
  }
}
function Confirm-AndRun {
  if (-not (Test-Path -LiteralPath $scriptPath)) {
    [System.Windows.MessageBox]::Show("Script not found:`n$scriptPath",'Admin Setup','OK','Warning') | Out-Null
    return
  }
  $answer = [System.Windows.MessageBox]::Show(
    "Run Clear Apps and Tray again?`n`nThis uninstalls removable programs and keeps the taskbar hidden.",
    'Confirm wipe','YesNo','Exclamation','No')
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
$window.FindName('BtnChrome').Add_MouseLeftButtonUp({ Start-ChromeFlow })
$window.FindName('BtnGrok').Add_MouseLeftButtonUp({ Start-GrokFlow })

$window.Add_ContentRendered({ Move-ToBottom })
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(3)
$timer.Add_Tick({ $window.Topmost = $true; Move-ToBottom })
$timer.Start()
[void]$window.ShowDialog()
