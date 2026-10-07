# Case study: 0xC1900101-0x2000D, "stuck at 28% for hours"

Identifying details removed; only the facts needed for the diagnosis are kept.

## Environment

- Desktop PC, 6-core engineering-sample CPU, GTX 1060, SSD system disk plus several hard disks
- Windows 11 Pro 23H2 (build 22631), upgrading to 26H2 (build 26300)
- Backup software with file-system filter drivers, and a RAM disk; the user's TEMP and TMP both pointed at the RAM disk
- Both Windows Update and the ISO had failed. On the latest attempt it sat at "28%" for hours after the reboot, and the user finally force-restarted

## The user's initial assumption

"0xC1900101 is a driver problem, so it must be the backup software's kernel drivers. Should I uninstall it completely?"

## Diagnosis

### 1. Take the error code straight from the Rollback log

`Rollback\setupact.log` contained:

```
Reporting post reboot event -> [0xC1900101, 0x2000D]
Remapping install error [0xC1900101] -> [0xC1900108] for telemetry
Current phase string : SafeOS,Start
Current bugcheck string: NULL
No crash detected.
BsdSummarize … FatalErrorCode:0
```

Conclusion: SAFE_OS phase, MIGRATE_DATA operation, **no crash recorded at all**. So not a driver bugcheck, and no need to download SetupDiag first.

### 2. Look at what the main log was doing last

`Panther\setupact.log` was 788 MB. The last thousands of lines were all:

```
MIG  Processing File: C:\Windows\SystemTemp\msedge_url_fetcher_xxxx_yyyy
     RECAPPLY: Recursively applied (delayed execution): F:\Windows\SystemTemp\msedge_url_fetcher_xxxx_yyyy
```

About 0.5–1 seconds per item, from 2 a.m. until the forced restart.

### 3. Count

`C:\Windows\SystemTemp` held **31,959** items:

- `chrome_url_fetcher_*`: 18,680
- `msedge_url_fetcher_*`: 12,771
- All **empty folders**: 0 files, 0 MB, accumulating for three years, starting about 18 months after the OS was installed

31,000 × 0.5–1 s ≈ 4–8 hours, matching "stuck at 28% for hours".

This accumulation is a known Chromium issue (e.g. Chromium issue 40283581; a Brave report of 800–1000 folders a week), but it had not been linked to upgrade failures before.

### 4. Check the suspected software

The backup software's name appeared over a thousand times in the main log, **all in the compatibility inventory and service lists** (`BuildCache`, `IsWindowsProvider`). None of them were Error lines. Conclusion: not directly related to this failure (highly likely); no need to uninstall.

### 5. Side finding

`setuperr.log` had `WinSetupMon::GetStablePath: Failed GetNtPath [<RAM disk>:\Tmp] (0xC0000034)`. TMP pointed at the RAM disk, which does not exist in SafeOS. Not fatal, but worth fixing.

## Fix

1. The user closed the browsers and deleted the empty folders themselves (SystemTemp went down to 508 items)
2. TEMP and TMP temporarily pointed back to C:
3. The backup software stayed installed
4. Upgrade run from the ISO with `setup.exe /auto upgrade /quiet /eula accept /dynamicupdate enable`

## Result

- The data-gathering step went from **over 6 hours to 5 minutes**
- About 90 minutes from start to reboot (including a 4 GB Dynamic Update download), then a dozen minutes or so to the sign-in screen
- Upgraded to 26H2 successfully; all 6 drivers of the backup software loaded normally
- After the upgrade the RAM disk no longer created its TEMP folders at boot. The user reconfigured it in the RAM disk software and rebooted to verify before pointing TEMP back at the RAM disk

## Lessons

1. **0xC1900101 does not mean "driver problem".** Check for a bugcheck first; if there is none, look at what the log was doing last
2. **"Stuck" is often "slow".** Count items, not bytes
3. **A product name in the log does not make it the culprit.** Check whether it appears in Error lines
4. **The TEMP variable does not apply to SYSTEM processes**; they always use `C:\Windows\SystemTemp`
5. **Monitoring produces many false alarms.** `Restartable`, `Rollback Enabled`, `Reboot required: no` and progress resetting to 0 are not warning signs
6. **Reboot to verify** custom disk or driver settings (such as a RAM disk) after the upgrade
