# Live monitor for a running Windows feature upgrade (downlevel phase only).
# Emits one line per noteworthy event; designed for Claude Code's Monitor tool.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File watch.ps1 [-PollSeconds 15] [-StaleMinutes 15]
#        watch.ps1 -Replay -LogPath <old setupact.log>   # run the filters over a finished log (testing / timeline)
param([int]$PollSeconds = 15, [int]$StaleMinutes = 15, [string]$LogPath = 'C:\$WINDOWS.~BT\Sources\Panther\setupact.log', [switch]$Replay)

$log = $LogPath
$t0 = Get-Date
while (-not (Test-Path -LiteralPath $log)) { if ($Replay -or ((Get-Date) - $t0).TotalMinutes -gt 10) { "NO_LOG $log not found - is setup running?"; exit 1 }; Start-Sleep 5 }

$fs = [IO.File]::Open($log, 'Open', 'Read', 'ReadWrite,Delete'); if (-not $Replay) { [void]$fs.Seek(0, 'End') }
$sr = New-Object IO.StreamReader($fs)
$lastBucket = -1; $lastWrite = Get-Date; $seen = @{}; $lastProg = [datetime]::MinValue

# Lines that look alarming but are normal (see references/log-guide.md).
$noise = 'Restartable:|DU::|DUImage|Rollback Enabled|RollbackOption|RollbackType|RollbackInitialize|Enqueue Operation|Add phase|Operation \(remaining\)|Operation \(completed\)|Reboot required: no|, Info\s+CBS |SYSPRP |, Info\s+MIG |Processing Registry|Processing File|RECAPPLY|IOCTL_STORAGE_QUERY_PROPERTY|IsRangeRequestSupported'
# Real failure signals: Error lines with an upgrade result code, or an actual rollback.
$failRx = '(?i), Error .*(0xC19[0-9A-F]{5}|SetupHost::Execute.*Result = 0x8)|Initiating rollback|Setup failed|Install failed|Crash 0x[0-9A-F]+ detected'
$rebootRx = 'Executing operation: .*(Orchestrate OS switch|Prepare SafeOS)'
# Milestones worth telling the user about.
$stepRx = 'Executing operation: (Gather data|Backup the recovery partition|Install Eula|Ensure suspended services)|DUImage: Searching for driver updates|Expanding express MumX|CompatData_|FCDCATHelper: Transfer: \[0x0 '

while ($true) {
  while (($l = $sr.ReadLine()) -ne $null) {
    $lastWrite = Get-Date
    $ts = if ($l.Length -ge 19) { $l.Substring(0, 19) } else { '' }
    # Per-step progress flips 0/100 many times a minute; report at most every 5 min of log time.
    if ($l -match 'Action progress: \[(\d+)%\]') { $pct = [int]$Matches[1]; $b = [math]::Floor($pct / 20) * 20; $now = [datetime]::MinValue; [void][datetime]::TryParse($ts, [ref]$now); if ($b -ne $lastBucket -and ($now - $lastProg).TotalMinutes -ge 5) { $lastBucket = $b; $lastProg = $now; "PROGRESS step $pct% | $ts (per-step progress; resets to 0 for each step)" }; continue }
    # Self-update relaunch at start: SetupHost exits with these and a new SetupHost continues.
    if ($l -match 'Result = 0x800705BB|Result = 0x800704D3') { if (-not $seen['relaunch']) { $seen['relaunch'] = 1; "INFO | $ts setup is relaunching itself after self-update (0x800705BB/0x800704D3 are expected here)" }; continue }
    if ($l -match $rebootRx) { if (-not $seen['reboot']) { $seen['reboot'] = 1; "REBOOT_SOON | $($l.Substring(0, [Math]::Min(200, $l.Length))) (reboot usually follows within ~2 min)" }; continue }
    if ($l -match $failRx) { $k = $l.Substring([Math]::Min(20, $l.Length)) -replace '\d', ''; if (-not $seen[$k]) { $seen[$k] = 1; "FAIL | $($l.Substring(0, [Math]::Min(220, $l.Length)))" }; continue }
    if ($l -match $noise) { continue }
    if ($l -match $stepRx) { $k = 'STEP:' + $Matches[0]; if (-not $seen[$k]) { $seen[$k] = 1; "STEP | $($l.Substring(0, [Math]::Min(200, $l.Length)))" } }
  }
  if ($Replay) { 'REPLAY_END'; exit 0 }
  if (-not (Get-Process SetupHost -ErrorAction SilentlyContinue)) {
    Start-Sleep 60   # setup relaunches itself after self-update; give it time
    if (-not (Get-Process SetupHost -ErrorAction SilentlyContinue)) { "SETUPHOST_GONE | $(Get-Date -Format HH:mm:ss) setup ended: reboot imminent, or it failed - check setuperr.log"; exit 0 }
  }
  if (((Get-Date) - $lastWrite).TotalMinutes -gt $StaleMinutes) { "STALE | log quiet for >$StaleMinutes min at $(Get-Date -Format HH:mm:ss)"; $lastWrite = Get-Date }
  Start-Sleep $PollSeconds
}
