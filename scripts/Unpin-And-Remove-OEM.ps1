# Unpin Outlook / Edge / Store from taskbar and uninstall where possible.
$ErrorActionPreference = 'Continue'

function Write-CleanLog {
  param([string]$Message, [string]$Level = 'INFO')
  $log = "$env:USERPROFILE\admin\scripts\Cleanup-Background.log"
  $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level, $Message
  New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
  $line | Tee-Object -FilePath $log -Append
}

function Add-CleanResult {
  param($List, [string]$Item, [string]$Status, [string]$Detail)
  $List.Add([pscustomobject]@{ Item = $Item; Status = $Status; Detail = $Detail })
}

function Unpin-TaskbarByName {
  param([string[]]$NamePatterns, $Results)
  try {
    $shell = New-Object -ComObject Shell.Application
    $apps = $shell.NameSpace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}')
  } catch {
    Add-CleanResult $Results 'Taskbar AppsFolder' 'NEED' $_.Exception.Message
    return
  }
  if (-not $apps) {
    Add-CleanResult $Results 'Taskbar AppsFolder' 'NEED' 'COM namespace unavailable'
    return
  }
  foreach ($item in @($apps.Items())) {
    $n = $item.Name
    $match = $false
    foreach ($pat in $NamePatterns) {
      if ($n -like $pat) { $match = $true; break }
    }
    if (-not $match) { continue }
    try {
      $unpinned = $false
      foreach ($v in @($item.Verbs())) {
        $vn = ($v.Name -replace '&','')
        if ($vn -match 'Unpin from taskbar|Unpin from Taskbar') {
          $v.DoIt()
          $unpinned = $true
          Add-CleanResult $Results "Taskbar unpin $n" 'FIXED' "verb=$vn"
          Write-CleanLog "Unpinned from taskbar: $n"
          break
        }
      }
      if (-not $unpinned) {
        Add-CleanResult $Results "Taskbar unpin $n" 'NEED' 'no unpin verb (maybe already unpinned)'
      }
    } catch {
      Add-CleanResult $Results "Taskbar unpin $n" 'NEED' $_.Exception.Message
    }
  }
}

function Remove-TaskbandPins {
  param($Results)
  try {
    $tb = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband'
    if (Test-Path $tb) {
      Remove-ItemProperty -Path $tb -Name 'Favorites' -Force -ErrorAction SilentlyContinue
      Remove-ItemProperty -Path $tb -Name 'FavoritesResolve' -Force -ErrorAction SilentlyContinue
      Remove-ItemProperty -Path $tb -Name 'FavoritesVersion' -Force -ErrorAction SilentlyContinue
    }
    Add-CleanResult $Results 'Taskband Favorites' 'FIXED' 'cleared pinned favorites values'
    Write-CleanLog 'Cleared Taskband Favorites registry values'
  } catch {
    Add-CleanResult $Results 'Taskband Favorites' 'NEED' $_.Exception.Message
  }
}

function Uninstall-EdgeOutlookStore {
  param($Results, [ref]$ChangesMade)

  # Edge via setup.exe
  try {
    $setup = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application","$env:ProgramFiles\Microsoft\Edge\Application" -Filter setup.exe -Recurse -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -match '\\Installer\\setup\.exe$' } |
      Select-Object -First 1
    if ($setup) {
      $p = Start-Process -FilePath $setup.FullName -ArgumentList '--uninstall','--system-level','--verbose-logging','--force-uninstall' -Wait -PassThru
      $ok = $p.ExitCode -in 0,19
      Add-CleanResult $Results 'Uninstall Microsoft Edge' $(if($ok){'FIXED'}else{'NEED'}) "setup.exe exit=$($p.ExitCode)"
      if ($ok) { $ChangesMade.Value = $true }
    } else {
      $wg = Start-Process winget.exe -ArgumentList @('uninstall','--id','Microsoft.Edge','-e','--silent','--accept-source-agreements','--force') -Wait -PassThru -NoNewWindow
      Add-CleanResult $Results 'Uninstall Microsoft Edge' $(if($wg.ExitCode -eq 0){'FIXED'}else{'NEED'}) "winget exit=$($wg.ExitCode)"
      if ($wg.ExitCode -eq 0) { $ChangesMade.Value = $true }
    }
  } catch {
    Add-CleanResult $Results 'Uninstall Microsoft Edge' 'NEED' $_.Exception.Message
  }

  # Outlook (new) + Mail/Calendar
  foreach ($name in @('Microsoft.OutlookForWindows','microsoft.windowscommunicationsapps')) {
    foreach ($pkg in @(Get-AppxPackage -Name $name -ErrorAction SilentlyContinue)) {
      try {
        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
        Add-CleanResult $Results "AppX remove $($pkg.Name)" 'FIXED' 'current user'
        $ChangesMade.Value = $true
      } catch {
        Add-CleanResult $Results "AppX remove $($pkg.Name)" 'NEED' $_.Exception.Message
      }
    }
    try {
      foreach ($pkg in @(Get-AppxPackage -Name $name -AllUsers -ErrorAction SilentlyContinue)) {
        try {
          Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
          Add-CleanResult $Results "AppX remove AllUsers $($pkg.Name)" 'FIXED' $pkg.PackageFullName
          $ChangesMade.Value = $true
        } catch {
          Add-CleanResult $Results "AppX remove AllUsers $($pkg.Name)" 'NEED' $_.Exception.Message
        }
      }
    } catch {
      Add-CleanResult $Results "AppX AllUsers $name" 'NEED' $_.Exception.Message
    }
    foreach ($prov in @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $name -or $_.PackageName -like "$name*" })) {
      try {
        Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
        Add-CleanResult $Results "AppX provisioned $($prov.DisplayName)" 'FIXED' 'removed provisioned'
        $ChangesMade.Value = $true
      } catch {
        Add-CleanResult $Results "AppX provisioned $($prov.DisplayName)" 'NEED' $_.Exception.Message
      }
    }
  }

  # Microsoft Store
  foreach ($pkg in @(Get-AppxPackage -Name 'Microsoft.WindowsStore' -ErrorAction SilentlyContinue)) {
    try {
      Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
      Add-CleanResult $Results 'AppX remove Microsoft.WindowsStore' 'FIXED' 'current user'
      $ChangesMade.Value = $true
    } catch {
      Add-CleanResult $Results 'AppX remove Microsoft.WindowsStore' 'NEED' $_.Exception.Message
    }
  }
  try {
    foreach ($pkg in @(Get-AppxPackage -Name 'Microsoft.WindowsStore' -AllUsers -ErrorAction SilentlyContinue)) {
      try {
        Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
        Add-CleanResult $Results 'AppX remove AllUsers Microsoft.WindowsStore' 'FIXED' $pkg.PackageFullName
        $ChangesMade.Value = $true
      } catch {
        Add-CleanResult $Results 'AppX remove AllUsers Microsoft.WindowsStore' 'NEED' $_.Exception.Message
      }
    }
  } catch {}
  foreach ($prov in @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq 'Microsoft.WindowsStore' })) {
    try {
      Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
      Add-CleanResult $Results 'AppX provisioned Microsoft.WindowsStore' 'FIXED' 'removed provisioned'
      $ChangesMade.Value = $true
    } catch {
      Add-CleanResult $Results 'AppX provisioned Microsoft.WindowsStore' 'NEED' $_.Exception.Message
    }
  }

  foreach ($name in @('Microsoft.StorePurchaseApp','Microsoft.Services.Store.Engagement')) {
    foreach ($pkg in @(Get-AppxPackage -Name $name -ErrorAction SilentlyContinue)) {
      try {
        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
        Add-CleanResult $Results "AppX remove $($pkg.Name)" 'FIXED' 'removed'
        $ChangesMade.Value = $true
      } catch {
        Add-CleanResult $Results "AppX remove $name" 'NEED' $_.Exception.Message
      }
    }
  }
}

# Standalone when executed directly
$isDotSourced = $MyInvocation.InvocationName -eq '.' -or $MyInvocation.Line -match '^\s*\.\s+'
if (-not $isDotSourced) {
  $results = New-Object System.Collections.Generic.List[object]
  $changes = $false
  Unpin-TaskbarByName -NamePatterns @('Microsoft Edge','Edge','Outlook','Mail','Microsoft Store','Store','Calendar') -Results $results
  Uninstall-EdgeOutlookStore -Results $results -ChangesMade ([ref]$changes)
  Remove-TaskbandPins -Results $results
  try {
    Stop-Process -Name explorer -Force -ErrorAction Stop
    Start-Sleep -Seconds 2
    Start-Process explorer.exe
    Add-CleanResult $results 'Explorer restart' 'FIXED' 'taskbar refresh'
  } catch {
    Add-CleanResult $results 'Explorer restart' 'NEED' $_.Exception.Message
  }
  $csv = "$env:USERPROFILE\admin\scripts\Cleanup-EdgeOutlookStore.csv"
  $results | Export-Csv $csv -NoTypeInformation -Encoding UTF8
  Write-CleanLog ("Summary FIXED={0} NEED={1} OK={2}" -f @($results|? Status -eq FIXED).Count, @($results|? Status -eq NEED).Count, @($results|? Status -eq OK).Count)
  Write-Host "Done. CSV: $csv ChangesMade=$changes"
  if ($changes) {
    Write-Host "Scheduling restart in 60s (shutdown /a to cancel)"
    shutdown.exe /r /t 60 /c "Cleanup: Edge/Outlook/Store removal - restart to finish"
  }
}
