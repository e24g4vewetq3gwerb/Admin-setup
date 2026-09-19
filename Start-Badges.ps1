# Two badges only: folder + PowerShell. No trash.
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
Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID } | ForEach-Object {
  try {
    $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)" -ErrorAction SilentlyContinue).CommandLine
    if ($cmd -and ($cmd -like '*Admin-Setup.ps1*' -or $cmd -like '*Start-Badges.ps1*' -or $cmd -like '*Clear-Apps-And-Tray.ps1*')) {
      Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
  } catch {}
}
Start-Sleep -Milliseconds 400
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Launch" WindowStyle="None" AllowsTransparency="True" Background="Transparent" ShowInTaskbar="False" Topmost="True" ResizeMode="NoResize" SizeToContent="WidthAndHeight">
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
$window = [Windows.Markup.XamlReader]::Parse($xaml)
$window.FindName('ImgFolder').Source = (Get-ExeImage (Join-Path $env:SystemRoot 'explorer.exe'))
$window.FindName('ImgPs').Source = (Get-ExeImage (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'))
function Move-ToBottom {
  $window.Left = [Math]::Max(0, ([System.Windows.SystemParameters]::PrimaryScreenWidth - $window.ActualWidth) / 2)
  $window.Top = [System.Windows.SystemParameters]::PrimaryScreenHeight - $window.ActualHeight - 16
}
$window.FindName('BtnFolder').Add_MouseLeftButtonUp({ Start-Process explorer.exe $env:USERPROFILE | Out-Null })
$window.FindName('BtnPs').Add_MouseLeftButtonUp({ Start-Process (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') | Out-Null })
$window.Add_ContentRendered({ Move-ToBottom })
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(3)
$timer.Add_Tick({ $window.Topmost = $true; Move-ToBottom })
$timer.Start()
[void]$window.ShowDialog()
