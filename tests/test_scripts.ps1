# Behaviour tests for the skill scripts, using synthetic fixtures. No third-party modules.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\test_scripts.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scripts = Join-Path $root 'skills\win-upgrade-doctor\scripts'
$fix = Join-Path $root 'tests\fixtures'
$exe = (Get-Process -Id $PID).Path
$fail = New-Object System.Collections.Generic.List[string]
function Assert($cond, $msg) { if ($cond) { "  ok   $msg" } else { "  FAIL $msg"; $fail.Add($msg) } }
function Run($file, [string[]]$argList) { & $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts $file) @argList 2>&1 | ForEach-Object { "$_" } }

"== parse =="
foreach ($ps in Get-ChildItem $scripts -Filter *.ps1) {
  $tokens = $null; $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($ps.FullName, [ref]$tokens, [ref]$errs)
  Assert ($errs.Count -eq 0) "$($ps.Name) parses ($($errs.Count) errors)"
}

"== watch.ps1 -Replay =="
$w = Run 'watch.ps1' @('-Replay', '-LogPath', (Join-Path $fix 'downlevel\setupact.log'))
Assert (@($w | Where-Object { $_ -like 'REBOOT_SOON*' }).Count -eq 1) 'exactly one REBOOT_SOON'
Assert (($w | Where-Object { $_ -like 'REBOOT_SOON*' }) -match 'Executing operation: Orchestrate OS switch') 'REBOOT_SOON comes from the executed OS switch, not the queued one'
Assert (-not ($w | Where-Object { $_ -like 'FAIL*' })) 'no FAIL on a healthy run (relaunch codes, rollback prep, CBS/SYSPRP reboot wording are noise)'
Assert (@($w | Where-Object { $_ -like 'INFO*relaunching*' }).Count -eq 1) 'self-update relaunch reported once as INFO'
Assert (@($w | Where-Object { $_ -like 'PROGRESS*' }).Count -le 8) 'progress throttled'
Assert ($w -match 'STEP .*Gather data') 'Gather data milestone reported'
Assert ($w[-1] -eq 'REPLAY_END') 'replay terminates'

"== diagnose.ps1 -SourcesDir (synthetic 0x2000D failure) =="
$d = Run 'diagnose.ps1' @('-SourcesDir', (Join-Path $fix 'failed\Sources'), '-Suspects', 'example_flt,ExampleBackup')
$dt = $d -join "`n"
Assert ($dt -match 'EXTEND 0x2000D = phase 2 SAFE_OS, operation 0x0D MIGRATE_DATA') 'extend code decoded'
Assert ($dt -match 'NO CRASH recorded') 'no-crash verdict'
Assert ($dt -match '120\s+C:\\Windows\\SystemTemp') 'bulk-migrated folder identified'
Assert ($dt -match 's/item') 'migration rate computed'
Assert ($dt -match 'examplebackup: 1 mentions' -and $dt -match 'example_flt: 1 mentions') 'comma-separated suspects split'
Assert ($dt -match 'inventory only, not evidence') 'suspects not blamed without Error lines'
Assert ($dt -notmatch 'IOCTL_STORAGE_QUERY_PROPERTY') 'noise filtered from setuperr output'

if ($fail.Count) { "`nFAILED: $($fail.Count)"; exit 1 } else { "`nOK: all script tests passed" }
