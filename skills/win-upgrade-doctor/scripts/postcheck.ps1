# Post-upgrade verification. Read-only.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File postcheck.ps1 [-Drivers snapman,file_protector] [-WithOldSize]
param([string[]]$Drivers = @(), [switch]$WithOldSize)

$ErrorActionPreference = 'SilentlyContinue'
$Drivers = @($Drivers | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$os = Get-CimInstance Win32_OperatingSystem
"=== Post-upgrade check ($(Get-Date -Format 'yyyy-MM-dd HH:mm')) ==="
"[INFO] OS: $($cv.EditionID) $($cv.DisplayVersion) build $($cv.CurrentBuild).$($cv.UBR) | installed $([DateTimeOffset]::FromUnixTimeSeconds($cv.InstallDate).LocalDateTime) | last boot $($os.LastBootUpTime)"
Get-ChildItem 'HKLM:\SYSTEM\Setup' | Where-Object PSChildName -like 'Source OS*' | ForEach-Object { $p = Get-ItemProperty $_.PSPath; "       history: $($_.PSChildName) <- was $($p.DisplayVersion) build $($p.CurrentBuild)" }
$lic = (Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'").LicenseStatus
if ($lic -contains 1) { '[OK] Windows is activated' } else { "[WARN] Activation status: $($lic -join ',') (1 = activated)" }

$bad = Get-PnpDevice -PresentOnly | Where-Object { $_.Status -notin 'OK', 'Unknown' }
if ($bad) { '[WARN] Devices with problems:'; $bad | ForEach-Object { "       $($_.Status) $($_.Class) $($_.FriendlyName)" } } else { '[OK] No problem devices' }
Get-CimInstance Win32_VideoController | ForEach-Object { "[INFO] GPU: $($_.Name) driver $($_.DriverVersion) ($($_.Status))" }
if ($Drivers.Count) { Get-CimInstance Win32_SystemDriver | Where-Object Name -in $Drivers | ForEach-Object { $lvl = if ($_.State -eq 'Running') { 'OK' } else { 'WARN' }; "[$lvl] driver $($_.Name): $($_.State)" } }
Get-Volume | Where-Object DriveLetter | Where-Object HealthStatus -ne 'Healthy' | ForEach-Object { "[WARN] Volume $($_.DriveLetter): $($_.HealthStatus)" }

$ev = Get-WinEvent -FilterHashtable @{LogName = 'System'; Level = 1, 2; StartTime = $os.LastBootUpTime } -ErrorAction SilentlyContinue
if ($ev) { "[INFO] Critical/Error System events since boot: $($ev.Count)"; $ev | Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { $m = ($_.Group[0].Message -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 2) -join ' '; "       {0}x {1}: {2}" -f $_.Count, $_.Name, $m.Substring(0, [Math]::Min(140, $m.Length)) } } else { '[OK] No Critical/Error System events since boot' }

foreach ($scope in 'User', 'Machine') { foreach ($v in 'TEMP', 'TMP') { $val = [Environment]::GetEnvironmentVariable($v, $scope); if ($val) { $exp = [Environment]::ExpandEnvironmentVariables($val); $lvl = if (Test-Path $exp) { 'OK' } else { 'FAIL' }; "[$lvl] $scope $v = $val$(if ($lvl -eq 'FAIL') { '  (folder missing! apps will fail to create temp files)' })" } } }

if (Test-Path C:\Windows.old) {
  # Sizing Windows.old by enumeration takes many minutes; only do it on request.
  $size = if ($WithOldSize) { ' {0:N1} GB,' -f ((Get-ChildItem C:\Windows.old -Recurse -File -Force | Measure-Object Length -Sum).Sum / 1GB) } else { '' }
  $age = ((Get-Date) - (Get-Item C:\Windows.old).CreationTime).Days
  "[INFO] C:\Windows.old exists,$size $age day(s) old - rollback possible for ~10 days; remove later via Settings > System > Storage > Temporary files"
}
"[INFO] C: free {0:N1} GB" -f ((Get-PSDrive C).Free / 1GB)
'=== end ==='
