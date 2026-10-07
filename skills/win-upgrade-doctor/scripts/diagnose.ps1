# Post-failure diagnosis for a Windows feature upgrade. Read-only.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File diagnose.ps1 [-Suspects acronis,snapman] [-TailLines 3000]
#        diagnose.ps1 -SourcesDir <copy of $WINDOWS.~BT\Sources>   # analyze logs copied elsewhere
param([string[]]$Suspects = @(), [int]$TailLines = 3000, [string]$SourcesDir = 'C:\$WINDOWS.~BT\Sources')

$ErrorActionPreference = 'SilentlyContinue'
$Suspects = @($Suspects | ForEach-Object { $_ -split ',' } | Where-Object { $_ })   # -File passes "a,b" as one string
function Short($s, $n = 230) { if ($s.Length -gt $n) { $s.Substring(0, $n) } else { $s } }
$bt = $SourcesDir.TrimEnd('\')
$rbLog = "$bt\Rollback\setupact.log"; $rbErr = "$bt\Rollback\setuperr.log"
$fallback = if ($PSBoundParameters.ContainsKey('SourcesDir')) { @() } else { @('C:\Windows\Panther\setupact.log', 'C:\Windows.old\Windows\Panther\setupact.log') }
$main = @("$bt\Panther\setupact.log") + $fallback | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$mainErr = if ($main) { Join-Path (Split-Path $main) 'setuperr.log' }

"=== Windows upgrade failure diagnosis ($(Get-Date -Format 'yyyy-MM-dd HH:mm')) ==="
foreach ($f in $rbLog, $main, "$bt\Rollback\setupmem.dmp", 'C:\Windows\Logs\SetupDiag\SetupDiagResults.xml') { if ($f -and (Test-Path -LiteralPath $f)) { $i = Get-Item -LiteralPath $f; "  found {0}  ({1:N1} MB, {2})" -f $f, ($i.Length / 1MB), $i.LastWriteTime } }

"`n--- 1. Final result (Rollback log) ---"
if (Test-Path -LiteralPath $rbLog) {
  $rb = Get-Content -LiteralPath $rbLog
  ($rb | Select-String 'Reporting post reboot event|Setup360Result\]|Remapping install error|Current phase string|Current bugcheck string|No crash detected|Crash 0x|Bugcheck parameter|Module name|FatalErrorCode:[1-9]|Initiating rollback/uninstall, phase = 0|Failed install count' | Select-Object -First 25).Line | ForEach-Object { '  ' + (Short $_) }
  $ev = $rb | Select-String 'Reporting post reboot event -> \[(0x[0-9A-Fa-f]+), (0x[0-9A-Fa-f]+)\]' | Select-Object -Last 1
  if ($ev) {
    $res = $ev.Matches[0].Groups[1].Value; $ext = [Convert]::ToInt32($ev.Matches[0].Groups[2].Value, 16)
    $phases = @{0 = 'UNKNOWN'; 1 = 'DOWNLEVEL'; 2 = 'SAFE_OS'; 3 = 'FIRST_BOOT'; 4 = 'OOBE_BOOT (second boot)'; 5 = 'UNINSTALL' }
    $ops = @{0x0 = 'UNKNOWN'; 0x1 = 'COPY_PAYLOAD'; 0x2 = 'DOWNLOAD_UPDATES'; 0x3 = 'INSTALL_UPDATES'; 0x4 = 'INSTALL_RECOVERY_ENVIRONMENT'; 0x5 = 'INSTALL_RECOVERY_IMAGE'; 0x6 = 'REPLICATE_OC'; 0x7 = 'INSTALL_DRIVERS'; 0x8 = 'PREPARE_SAFE_OS'; 0x9 = 'PREPARE_ROLLBACK'; 0xA = 'PREPARE_FIRST_BOOT'; 0xB = 'PREPARE_OOBE_BOOT'; 0xC = 'APPLY_IMAGE'; 0xD = 'MIGRATE_DATA'; 0xE = 'SET_PRODUCT_KEY'; 0xF = 'ADD_UNATTEND'; 0x10 = 'ADD_DRIVER'; 0x11 = 'ENABLE_FEATURE'; 0x12 = 'DISABLE_FEATURE'; 0x13 = 'REGISTER_ASYNC_PROCESS'; 0x14 = 'REGISTER_SYNC_PROCESS'; 0x15 = 'CREATE_FILE'; 0x16 = 'CREATE_REGISTRY'; 0x17 = 'BOOT'; 0x18 = 'SYSPREP'; 0x19 = 'OOBE'; 0x1A = 'BEGIN_FIRST_BOOT'; 0x1B = 'END_FIRST_BOOT'; 0x1C = 'BEGIN_OOBE_BOOT'; 0x1D = 'END_OOBE_BOOT'; 0x1E = 'PRE_OOBE'; 0x1F = 'POST_OOBE'; 0x20 = 'ADD_PROVISIONING_PACKAGE' }
    $ph = $ext -shr 16; $op = $ext -band 0xFF
    "  => RESULT $res - EXTEND 0x{0:X} = phase {1} {2}, operation 0x{3:X2} {4}" -f $ext, $ph, $phases[$ph], $op, $ops[$op]
  }
  $crash = $rb | Select-String 'Crash 0x[0-9A-F]+ detected|Current bugcheck string: (?!NULL)'
  if ($crash) { '  => CRASH RECORDED: driver/hardware failure likely. Check setupmem.dmp and the module name above.' } elseif ($rb | Select-String 'No crash detected') { '  => NO CRASH recorded: not a driver bugcheck. Look at what setup was doing last (section 3) and whether the PC was force-restarted.' }
  if (Test-Path -LiteralPath $rbErr) { "  rollback setuperr.log (non-noise):"; Get-Content -LiteralPath $rbErr | Where-Object { $_ -notmatch 'IOCTL_STORAGE_QUERY_PROPERTY|telemetry' } | Select-Object -Last 10 | ForEach-Object { '    ' + (Short $_) } }
} else { '  No Rollback log. Either setup failed before reboot (see section 2) or logs were cleaned.' }

"`n--- 2. Errors near the end (setuperr.log, noise filtered) ---"
if ($mainErr -and (Test-Path -LiteralPath $mainErr)) {
  $noise = 'IOCTL_STORAGE_QUERY_PROPERTY|IsRangeRequestSupported|TableTextServiceMig|BRIDGEMIG|WinsockMig|CSIAgent: Invalid xml|pSPRemoveUpgradeRegTree|adammigrate|PITR|BFSVC: USE_EX_BINS'
  Get-Content -LiteralPath $mainErr | Where-Object { $_.Trim() -and $_ -notmatch $noise } | Select-Object -Last 20 | ForEach-Object { '  ' + (Short $_) }
} else { '  setuperr.log not found' }

"`n--- 3. What setup was doing last (main setupact.log) ---"
if ($main) {
  $tail = Get-Content -LiteralPath $main -Tail $TailLines
  "  last line: " + (Short $tail[-1])
  ($tail | Select-String 'Executing operation:' | Select-Object -Last 3).Line | Where-Object { $_ } | ForEach-Object { '  op: ' + (Short $_) }
  $paths = $tail | Where-Object { $_ -match 'Processing (File|Registry): (.+)$' } | ForEach-Object { $p = $Matches[2]; ($p -replace '\\[^\\]+$', '') -replace '_\d+(_\d+)?$', '' }
  if ($paths) {
    "  migration activity in last $TailLines lines (top parent paths):"
    $paths | Group-Object | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { "    {0,6}  {1}" -f $_.Count, $_.Name }
    $first = ($tail | Where-Object { $_ -match 'Processing File' } | Select-Object -First 1).Substring(0, 19); $last = ($tail | Where-Object { $_ -match 'Processing File' } | Select-Object -Last 1).Substring(0, 19)
    $n = ($tail | Where-Object { $_ -match 'Processing File' }).Count
    $secs = ([datetime]$last - [datetime]$first).TotalSeconds
    if ($n -gt 10 -and $secs -gt 0) { "    rate: {0} items in {1:N0} s = {2:N2} s/item" -f $n, $secs, ($secs / $n) }
    '  => If one folder dominates and the user force-restarted, the real cause is slow migration of that folder. Count its items on the live system.'
  }
}

"`n--- 4. Suspect software ---"
if ($Suspects.Count -and $main) {
  $rx = ($Suspects | ForEach-Object { [regex]::Escape($_) }) -join '|'
  $hits = @{}; $errHits = @()
  $r = [IO.File]::OpenText($main)
  while (($l = $r.ReadLine()) -ne $null) { if ($l -match "(?i)($rx)") { $k = $Matches[1].ToLower(); $hits[$k]++; if ($l -match ', (Error|Warning) ') { $errHits += Short $l } } }
  $r.Close()
  $hits.GetEnumerator() | ForEach-Object { "  {0}: {1} mentions" -f $_.Key, $_.Value }
  if ($errHits) { '  in Error/Warning lines (evidence only if near the failure time / phase):'; $errHits | Select-Object -First 10 | ForEach-Object { '    ' + $_ } } else { '  => No Error/Warning lines mention the suspects: mentions are inventory only, not evidence.' }
  $sa = "$bt\Rollback\setupapi\setupapi.dev.log"; if (Test-Path -LiteralPath $sa) { $f = Select-String -LiteralPath $sa -Pattern "(?i)($rx)" | Select-Object -First 5; if ($f) { '  setupapi.dev.log mentions:'; $f | ForEach-Object { '    ' + (Short $_.Line) } } }
} elseif (-not $Suspects.Count) { '  (pass -Suspects name1,name2 to check specific drivers/software)' }

"`n--- 5. SetupDiag auto-result ---"
$sd = 'C:\Windows\Logs\SetupDiag\SetupDiagResults.xml'
if (Test-Path $sd) { ([xml](Get-Content $sd)).SelectNodes('//*[local-name()="Name" or local-name()="Description" or local-name()="FailureData" or local-name()="Remediation"]') | Where-Object { $_.InnerText } | Select-Object -First 8 | ForEach-Object { '  ' + $_.LocalName + ': ' + (Short $_.InnerText 300) } } else { '  none' }
"=== end ==="
