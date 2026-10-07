# Windows feature-upgrade pre-flight check. Read-only: changes nothing.
# Run as Administrator for complete results.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File preflight.ps1 [-IsoPath D:\win.iso]
param([string]$IsoPath)

$ErrorActionPreference = 'SilentlyContinue'
function Out-Item($level, $title, $detail) { "[{0}] {1}" -f $level, $title; if ($detail) { $detail -split "`n" | ForEach-Object { "       $_" } } }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
"=== Windows upgrade pre-flight ($(Get-Date -Format 'yyyy-MM-dd HH:mm')) ==="
if (-not $isAdmin) { Out-Item 'WARN' 'Not running as Administrator - some checks will be incomplete' }

# 1. Current OS
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
# InstallLanguage (LCID) is the language setup matches against; InstalledUICulture can be wrong (e.g. zh-HK on zh-TW installs)
$uiLang = try { [Globalization.CultureInfo]::new([Convert]::ToInt32((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language').InstallLanguage, 16)).Name } catch { [Globalization.CultureInfo]::InstalledUICulture.Name }
Out-Item 'INFO' "Current OS: $($cv.EditionID) $($cv.DisplayVersion) build $($cv.CurrentBuild).$($cv.UBR) | install language $uiLang | arch $env:PROCESSOR_ARCHITECTURE"
$hist = Get-ChildItem 'HKLM:\SYSTEM\Setup' | Where-Object PSChildName -like 'Source OS*' | ForEach-Object { $p = Get-ItemProperty $_.PSPath; "$($_.PSChildName -replace 'Source OS \(Updated on ','' -replace '\)','') : was $($p.DisplayVersion) build $($p.CurrentBuild)" }
if ($hist) { Out-Item 'INFO' 'Previous feature upgrades (registry Source OS keys)' ($hist -join "`n") }

# 2. Leftovers from previous attempts
$bt = 'C:\$WINDOWS.~BT'
if (Test-Path -LiteralPath $bt) {
  $rb = Join-Path $bt 'Sources\Rollback\setupact.log'
  $evt = if (Test-Path -LiteralPath $rb) { Select-String -LiteralPath $rb -Pattern 'Reporting post reboot event -> \[(0x[0-9A-Fa-f]+), (0x[0-9A-Fa-f]+)\]' | Select-Object -Last 1 }
  if ($evt) { Out-Item 'WARN' "Previous attempt rolled back: $($evt.Matches[0].Groups[1].Value) - $($evt.Matches[0].Groups[2].Value)" "Back up $bt\Sources\Rollback and Panther logs before retrying; setup will overwrite them." }
  else { Out-Item 'INFO' "$bt exists (previous or in-progress attempt)" }
}
$pend = @()
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pend += 'CBS RebootPending' }
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pend += 'WindowsUpdate RebootRequired' }
if ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager').PendingFileRenameOperations) { $pend += 'PendingFileRenameOperations' }
if ($pend) { Out-Item 'WARN' "Reboot pending: $($pend -join ', ')" 'Reboot once before starting the upgrade.' } else { Out-Item 'OK' 'No pending reboot' }

# 3. SystemTemp bloat (migrated item by item, ~0.5-1 s each)
$st = 'C:\Windows\SystemTemp'
if (Test-Path $st) {
  $items = Get-ChildItem -LiteralPath $st -Force
  $groups = $items | Group-Object { $_.Name -replace '[_\d]+$', '' } | Sort-Object Count -Descending | Select-Object -First 5
  $fetch = ($items | Where-Object Name -match '^(chrome|msedge)_url_fetcher_').Count
  $detail = ($groups | ForEach-Object { "{0,7}  {1}*" -f $_.Count, $_.Name }) -join "`n"
  $hrs = [math]::Round($items.Count * 0.75 / 3600, 1)
  if ($items.Count -ge 5000) { Out-Item 'FAIL' "$st has $($items.Count) items (url_fetcher dirs: $fetch) - estimated +$hrs h of migration in SafeOS" ($detail + "`nClose Chrome/Edge, verify the folders are empty, then the user deletes them:`nGet-ChildItem C:\Windows\SystemTemp -Directory | Where-Object Name -match '^(chrome|msedge)_url_fetcher_' | Remove-Item -Recurse -Force") }
  elseif ($items.Count -ge 1000) { Out-Item 'WARN' "$st has $($items.Count) items (url_fetcher dirs: $fetch) - estimated +$hrs h" $detail }
  else { Out-Item 'OK' "$st has $($items.Count) items" }
}
foreach ($d in 'C:\Windows\Temp', 'C:\Windows\SoftwareDistribution\Download', 'C:\Windows\Logs\CBS') {
  $n = (Get-ChildItem -LiteralPath $d -Recurse -Force | Measure-Object).Count
  if ($n -ge 20000) { Out-Item 'WARN' "$d has $n items - consider cleanup (Disk Cleanup / Storage Sense)" }
}

# 4. TEMP / TMP locations
$drives = @{}; Get-CimInstance Win32_LogicalDisk | ForEach-Object { $drives[$_.DeviceID] = $_ }
$ramBus = Get-PnpDevice | Where-Object { $_.FriendlyName -match 'RAM ?Disk|SoftPerfect|ImDisk|Primo|Virtual Bus' }
foreach ($scope in 'User', 'Machine') { foreach ($v in 'TEMP', 'TMP') {
  $val = [Environment]::GetEnvironmentVariable($v, $scope); if (-not $val) { continue }
  $exp = [Environment]::ExpandEnvironmentVariables($val); $dl = $exp.Substring(0, 2).ToUpper()
  if ($dl -ne 'C:' -and $dl -match '^[A-Z]:$') {
    $d = $drives[$dl]; $why = if (-not $d) { 'drive does not exist' } elseif ($d.DriveType -eq 2) { 'removable drive' } elseif ($ramBus) { 'non-system drive; a RAM disk driver is installed' } else { 'non-system drive' }
    Out-Item 'WARN' "$scope $v = $val ($why)" "SafeOS cannot see this drive (setup monitor driver fails). Point it to %USERPROFILE%\AppData\Local\Temp during the upgrade, restore afterwards."
  } elseif (-not (Test-Path $exp)) { Out-Item 'WARN' "$scope $v = $val does not exist" }
} }
if (-not ($drives.Keys | Where-Object { $_ -ne 'C:' } | ForEach-Object { [Environment]::GetEnvironmentVariable('TEMP', 'User') -like "$_*" })) { Out-Item 'OK' 'User TEMP is on C:' }

# 5. Third-party filter / storage drivers
if ($isAdmin) {
  $flt = fltmc filters 2>$null | Select-Object -Skip 3 | ForEach-Object { ($_ -split '\s+')[0] } | Where-Object { $_ }
  $msFlt = 'bindflt|cldflt|CldFlt|FileCrypt|FileInfo|luafv|npsvctrig|storqosflt|wcifs|Wof|WdFilter|bfs|UCPD|applockerfltr|PROCMON\d*|gameflt|iorate|dfs|FileQos|wtd|SgrmAgent|mssecflt|MsSecCore|Ntfs|CimFS|AppVVemgr|ProjFS|PrjFlt|unionfs'
  $third = $flt | Where-Object { $_ -notmatch "^($msFlt)$" }
  if ($third) { Out-Item 'WARN' "Third-party file-system filter drivers loaded: $($third -join ', ')" 'Typical sources: backup, antivirus/EDR, encryption, sync tools. Pause their real-time protection before upgrading; remove only if logs implicate them.' }
  else { Out-Item 'OK' 'No third-party file-system filter drivers' }
}
$known = 'snapman|file_protector|file_tracker|fltsrv|tib_mounter|tdrpman|aswSP|aswArPot|klif|kneps|bdfsfltr|eamonm|epfwwfp|SentinelMonitor|CSAgent|cyverak|vsdatant|DeepFrz|spvve|spvdbus|imdisk|sptd|dtlitescsibus|VeraCrypt|dcrypt|iaStorA|iaStorAC|iaStorAVC'
$drv = Get-CimInstance Win32_SystemDriver | Where-Object { $_.Name -match "^($known)$" -and $_.State -eq 'Running' } | ForEach-Object { $_.Name }
if ($drv) { Out-Item 'INFO' "Known high-risk third-party drivers running: $($drv -join ', ')" 'Not a problem by themselves; check these first if the upgrade fails at BOOT (0x20017/0x40017) or SYSPREP (0x30018).' }

# 6. Disk space and system partitions
$free = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
if ($free -lt 25) { Out-Item 'FAIL' "C: free space $free GB (need ~25-40 GB)" } elseif ($free -lt 40) { Out-Item 'WARN' "C: free space $free GB" } else { Out-Item 'OK' "C: free space $free GB" }
$esp = Get-Partition | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' }
if (($esp | Measure-Object).Count -gt 1) { Out-Item 'WARN' "$(($esp | Measure-Object).Count) EFI system partitions on disks $((($esp.DiskNumber | Sort-Object -Unique) -join ', '))" 'Multiple system partitions can cause 0x...-0x20009. Disconnect disks holding an old OS if the upgrade fails there.' }
$re = (reagentc /info 2>$null | Out-String); if ($re -match 'Disabled') { Out-Item 'WARN' 'Windows RE is disabled' }

# 7. Upgrade blockers from the last compat scan
$cx = Get-ChildItem -LiteralPath "$bt\Sources\Panther" -Filter 'CompatData_*.xml' | Sort-Object LastWriteTime | Select-Object -Last 1
if ($cx) { $hard = Select-String -LiteralPath $cx.FullName -Pattern 'BlockingType="Hard"'; if ($hard) { Out-Item 'FAIL' "Last compat scan ($($cx.LastWriteTime)) has hard blocks" (($hard | ForEach-Object { $_.Line.Trim() }) -join "`n") } else { Out-Item 'OK' "Last compat scan ($($cx.LastWriteTime)) has no hard blocks" } }

# 8. ISO match
if ($IsoPath) {
  if (-not (Test-Path $IsoPath)) { Out-Item 'FAIL' "ISO not found: $IsoPath" }
  else {
    $img = Get-DiskImage -ImagePath $IsoPath; $mountedHere = $false
    if (-not $img.Attached) { $img = Mount-DiskImage -ImagePath $IsoPath -PassThru; $mountedHere = $true }
    $dl = ($img | Get-Volume).DriveLetter
    $wim = @("${dl}:\sources\install.wim", "${dl}:\sources\install.esd") | Where-Object { Test-Path $_ } | Select-Object -First 1
    $match = $null; $list = @()
    Get-WindowsImage -ImagePath $wim | ForEach-Object { $d = Get-WindowsImage -ImagePath $wim -Index $_.ImageIndex; $list += "[$($d.ImageIndex)] $($d.EditionId) build $($d.Version) lang $($d.Languages -join ',') arch $(@{0='x86';5='ARM';9='x64';12='ARM64'}[[int]$d.Architecture])"; if ($d.EditionId -eq $cv.EditionID -and ($d.Languages -contains $uiLang)) { $match = $d } }
    if ($match) { Out-Item 'OK' "ISO ($($dl):) contains a matching image: $($match.EditionId) $uiLang build $($match.Version)" ($list -join "`n") }
    else { Out-Item 'FAIL' "ISO has no image matching $($cv.EditionID) / $uiLang - keeping files and apps will not be offered" ($list -join "`n") }
    if ($mountedHere) { "       (ISO left mounted at ${dl}: for setup.exe)" }
  }
}
"=== end ==="
