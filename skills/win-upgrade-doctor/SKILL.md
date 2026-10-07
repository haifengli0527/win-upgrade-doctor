---
name: win-upgrade-doctor
description: Pre-flight checks, live monitoring, failure diagnosis and post-upgrade cleanup for Windows 10/11 feature updates and in-place upgrades (e.g. 23H2 to 24H2/25H2/26H2, Windows 10 to 11). Use this skill whenever the user mentions a failed Windows upgrade, 0xC1900101 or any 0xC19xxxxx / 0x800xxxxx setup error, "stuck at xx%", "Working on updates" taking hours, "Restoring your previous version of Windows", rollback, SetupDiag, setupact.log / setuperr.log / $WINDOWS.~BT / Panther logs, running setup.exe from an ISO, a feature update that keeps failing in Windows Update, whether an upgrade will succeed, letting an upgrade run unattended, or checking and restoring things after an upgrade (Windows.old, TEMP, drivers) — even if they never say "diagnose". 也適用於中文：升級失敗、卡在 xx%、正在還原先前的 Windows 版本、0xC1900101、升級前檢查、升級後收尾。
---

# Windows Upgrade Doctor

Help the user through a Windows **feature update / in-place upgrade**: find landmines before upgrading, read progress correctly while it runs, find the real cause after a failure, and tidy up afterwards. Reply in the user's language.

The value of this skill is **avoiding detours**. Upgrade logs are huge and noisy, full of lines that look like errors but are harmless, and the error codes are vague (0xC1900101 only means "it rolled back"). Without a method it is easy to jump to conclusions (blaming the antivirus straight away) or mistake normal behaviour for failure. The workflow and references below were distilled from misreadings in a real case.

## Work out where the user is

| Situation | Go to |
|---|---|
| Not upgraded yet, wants a check, or retrying after a failure | [A. Pre-flight](#a-pre-flight) |
| Upgrade is running (PC still in the old OS) | [B. Live monitoring](#b-live-monitoring) |
| Already rolled back, or was force-restarted while "stuck" | [C. Failure diagnosis](#c-failure-diagnosis) |
| Upgrade succeeded, back at the desktop | [D. After the upgrade](#d-after-the-upgrade) |
| General questions: ISO or Windows Update, does 26H2 need a clean install, can I rename my user folder… | `references/scenarios.md` |

## Safety and consent

An upgrade touches the whole machine. These rules protect the user; do not skip them:

- **Let the user run deletions themselves.** Give the command, explain what it removes and why it is safe, but do not delete. Before suggesting a deletion, prove what the content is (e.g. "31,451 folders, 0 files, 0 MB").
- **Get explicit consent before starting an upgrade.** `/eula accept` accepts the licence terms on the user's behalf and `/auto upgrade` reboots automatically. Say both before running it.
- **Be upfront about Claude's limits.** Claude runs on the user's PC and **goes offline at the first reboot**. SafeOS, first boot and OOBE are invisible until the user is back at the desktop and starts Claude again. Never promise to "keep watching after the reboot".
- **Advise against force-restarting while it "looks stuck".** A forced restart itself produces a 0xC1900101 rollback, and many "hangs" are just slow processing (see the case study).
- Record original values before changing environment variables, disabling services, etc., so they can be restored afterwards.

## A. Pre-flight

Run `scripts/preflight.ps1` (read-only, except that `-IsoPath` mounts the ISO; run as Administrator for complete results):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>/scripts/preflight.ps1" [-IsoPath D:\xxx.iso]
```

It checks and labels each item `[OK] / [WARN] / [FAIL]`:

1. Current version, edition, install language, leftovers from earlier attempts (`$WINDOWS.~BT`, `0xC19…` results)
2. **Item count in `C:\Windows\SystemTemp`**, especially empty `chrome_url_fetcher_*` / `msedge_url_fetcher_*` folders left by Chromium-based browser updaters. Every item there is migrated one by one during the upgrade at roughly 0.5–1 s each, so **tens of thousands means hours**, which looks like being stuck at 20–30%
3. Whether user or system TEMP / TMP point at a RAM disk, removable drive or missing path (those drives do not exist inside SafeOS)
4. Loaded third-party file-system filter drivers (`fltmc`) and known risky storage/security drivers: backup, antivirus/EDR, encryption, RAM disk, virtual drives
5. Free space on C:, pending reboot, multiple EFI system partitions across disks
6. With an ISO: whether edition, language and build match the running system (if not, keeping files and apps is not offered)

Translate the results into plain language with an impact and a recommended action for each item. Only recommend action where there is evidence. **Do not tell the user to uninstall software just because it is installed** — pause or disable first, and talk about removal only once the logs implicate it.

## B. Live monitoring

### Starting the upgrade (after consent)

```powershell
<ISO drive>:\setup.exe /auto upgrade /quiet /eula accept /dynamicupdate enable
```

- `/dynamicupdate enable` downloads and integrates the latest cumulative update first (can be several GB and 10–30 extra minutes), so the result is fully patched and setup itself runs a fixed version. Use `disable` on a poor connection or to go faster.
- Within the first minute you may see `0x800705BB`, `0x800704D3` or `CheckUserInterrupt` — **usually setup relaunching itself after a self-update** (SetupHost gets a new PID; compare the documented code `0xC1900129 UPDATEMEDIA_REQUESTED`). Check that SetupHost is still running and the log is still growing; **do not rerun setup in a hurry**.

### Watching the log

Run `scripts/watch.ps1` with the Monitor tool (30 minutes per run at most; re-arm on expiry):

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>/scripts/watch.ps1"
```

It only prints events worth reporting: `STEP` (milestone started), `PROGRESS` (at most every 5 minutes), `INFO` (e.g. self-update relaunch), `REBOOT_SOON`, `FAIL`, `STALE` (log quiet for 15 minutes) and `SETUPHOST_GONE`. When reporting, say what it is doing, whether that is normal and what comes next, in a sentence or two.

After changing the filters, replay a finished log with `-Replay -LogPath <old setupact.log>` to confirm there are no false alarms and the reboot warning still fires before using it on a live upgrade.

Before interpreting anything, read the harmless-messages list and the phase timeline in `references/log-guide.md`. **`Action progress` is per step, from 0 to 100%, and resets repeatedly.** `Rollback Enabled`, `Restartable: [no]`, `Reboot required: no`, and the pending-operation tables are neither failures nor reboot signals.

If the user is away from the PC, `REBOOT_SOON` (`Executing operation: Orchestrate OS switch`) is the only reliable reboot warning, usually only seconds to about two minutes ahead. When it fires: briefly summarise progress, give a success estimate with a confidence level, remind the user not to force-restart after the reboot, then let it restart naturally. Send a PushNotification if available.

## C. Failure diagnosis

Run `scripts/diagnose.ps1` (read-only). It:

1. Finds `Reporting post reboot event -> [0xC19xxxxx, 0xNNNNN]` in `$WINDOWS.~BT\Sources\Rollback\setupact.log`. **That line already contains the full result and extend code**, so SetupDiag is not needed first
2. Decides **whether anything crashed**: `Current bugcheck string`, `No crash detected`, `FatalErrorCode`, `setupmem.dmp`
3. Shows `Current phase string`, **what the main `setupact.log` was doing last** (the most repeated activity at the end), and the processing rate
4. Searches for suspect names the user gives, separating "only in inventory lists" from "in Error/Warning lines"
5. Falls back to `C:\Windows\Panther`, `C:\Windows.old` or `C:\Windows\Logs\SetupDiag\SetupDiagResults.xml` if the main log was cleaned up

`-SourcesDir` analyses a copy of `$WINDOWS.~BT\Sources` stored elsewhere.

### Order of reasoning (to avoid jumping to conclusions)

1. **Decode the extend code first**: first digit is the phase, last two digits the operation (`references/error-codes.md`)
2. **Bugcheck or dump?** Yes: driver or hardware, find the module from the dump or bugcheck parameters. No: carry on
3. **What was it doing last?** If it is masses of repeated migration lines (`Processing File`, `RECAPPLY`) and the user force-restarted, **the real cause is "too slow, then interrupted"**, not a driver. Find the path being processed in bulk
4. **Look for evidence against suspects.** A name that only appears in the compatibility inventory or service list is not evidence. Appearing in Error lines, as a bugcheck module, or as a failed install in setupapi.dev.log is
5. Give recommendations from the common causes in `references/error-codes.md`

### Reporting format

A table of: result code and extend code, phase, operation, crash or not, last activity, suspicious components. Label every conclusion:

- **Confirmed**: stated directly in the log
- **Highly likely**: several pieces of evidence point to it, but it needs inference
- **Needs verification**: only indirect signs or missing data

Finish with **ordered** next steps (cheapest and best-evidenced first) and what to watch for on the retry.

## D. After the upgrade

Run `scripts/postcheck.ps1 [-Drivers name1,name2]` (read-only, about 20 seconds). It checks version and build, activation, upgrade history, problem devices, whether previously suspected drivers load, Critical/Error events since boot, whether the TEMP/TMP folders exist, and Windows.old. Sizing Windows.old takes minutes, so add `-WithOldSize` only when needed.

Then undo temporary changes made before the upgrade (TEMP/TMP, disabled services, paused protection), and remind the user:

- **RAM disk users**: confirm the RAM disk still creates its TEMP folders at boot. An upgrade can lose the RAM disk software's settings, and TEMP pointing at a missing folder breaks many applications. **Have the user reboot once to verify** before pointing TEMP back at the RAM disk
- `Windows.old` allows going back for about 10 days. Once stable, remove it via Settings → System → Storage → Temporary files
- Common but usually harmless boot events are listed under "After the upgrade" in `references/scenarios.md`

## References

| File | Read when |
|---|---|
| `references/error-codes.md` | Decoding any result or extend code, or giving the matching advice |
| `references/log-guide.md` | Reading logs, writing or tuning monitor filters, deciding whether a line is a problem |
| `references/scenarios.md` | General upgrade questions and common community issues (stuck at %, boot loops, specific software, ISO vs WU, 26H2…) |
| `references/case-study.md` | The full real diagnosis, or any "stuck for hours + 0xC1900101" case |
