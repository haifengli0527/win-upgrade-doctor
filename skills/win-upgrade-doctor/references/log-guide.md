# Reading upgrade logs

## Contents

1. Where the logs are
2. How to read huge logs
3. Real warning signs
4. Harmless messages (easy to misread)
5. Timeline of a normal upgrade
6. Designing monitor filters

## 1. Where the logs are

| When | Path | Contents |
|---|---|---|
| Preparing, SafeOS | `C:\$WINDOWS.~BT\Sources\Panther\setupact.log`, `setuperr.log` | Main log; can grow to hundreds of MB |
| Compatibility scan | `C:\$WINDOWS.~BT\Sources\Panther\CompatData_*.xml` | `BlockingType="Hard"` blocks the upgrade |
| After rollback | `C:\$WINDOWS.~BT\Sources\Rollback\setupact.log`, `setuperr.log` | **The final error code is here** |
| Crash info during rollback | `Rollback\setupmem.dmp`, `Rollback\*.evtx`, `Rollback\setupapi\setupapi.dev.log` | Check setupapi for 0x30018 |
| After success | `C:\Windows\Panther\setupact.log`, `C:\Windows\Panther\NewOsSetup\` | |
| SetupDiag auto-run | `C:\Windows\Logs\SetupDiag\SetupDiagResults.xml` | Setup runs SetupDiag itself on failure |
| Upgrade history | Registry `HKLM\SYSTEM\Setup\Source OS (Updated on …)` | One entry with the previous version per full upgrade |

Notes:

- The paths contain `$`; in PowerShell use single quotes or `-LiteralPath`
- In SafeOS the system drive often has another letter (`F:\$WINDOWS.~BT` in the log). This is normal
- The next run of setup overwrites `$WINDOWS.~BT`, so **back up the previous logs** before retrying

## 2. How to read huge logs

- Do not load the whole file. Use `Get-Content -Tail N`, or stream it line by line with `[IO.File]::OpenText()` (about a minute for 800 MB)
- Final result: search the Rollback setupact.log for `Reporting post reboot event`, `Setup360Result`, `Current phase string`, `bugcheck`
- Where it stalled: the **most repeated activity** and **the paths being processed** in the last 200–500 lines of the main log. `MIG Processing File: <path>` followed by `RECAPPLY: Recursively applied … <path>` means files are being migrated one at a time
- Rate: count how many items of one kind were processed and the time between the first and the last, work out seconds per item, multiply by what is left

## 3. Real warning signs

| Signal | Meaning |
|---|---|
| `Initiating rollback/uninstall` in the Rollback log | Rolling back |
| `Reporting post reboot event -> [0xC19xxxxx, 0xNNNNN]` | Final result and extend code |
| `Crash 0x… detected`, `Bugcheck parameter`, `Module name:` | A crash happened; the module is the suspect |
| `Current bugcheck string: <not NULL>` | A crash happened |
| `setupmem.dmp` exists | A crash dump exists |
| A `.sys` driver or product name in an **Error** line | Only this counts as evidence against that software |
| `BlockingType="Hard"` in `CompatData_*.xml` | Blocked; the upgrade will not start |
| **No new lines for 15–30 minutes** in the main log and SetupHost CPU not moving | Possibly really stuck |

## 4. Harmless messages (easy to misread)

These also appear in successful upgrades. They are not failures or reboot signals:

| Message | What it actually means |
|---|---|
| `IOCTL_STORAGE_QUERY_PROPERTY failed: 0x1` | Disk property query failed; floods on machines with many disks or RAID |
| `IsRangeRequestSupported … 0x80040154` | Checking whether the download server supports range requests |
| `DU::CDUSession::Search … hr = 0x80070057` | Dynamic Update failed to set a scan property; the search continues |
| `CheckUserInterrupt … 0x800704D3`, `ExecuteInstallMode … 0x800705BB` (right after start) | Setup relaunching after self-update; SetupHost gets a new PID |
| `MoSetupPlatform: Restartable: [no]` | This stage cannot resume mid-way if interrupted; just a setting |
| `Rollback Enabled via scenario detection`, `RollbackOption`, `RollbackType`, `RollbackInitialize` | Preparing the ability to roll back |
| `OPERATIONTRACK: Enqueue Operation`, `Add phase`, `Operation (remaining)` and step tables | Scheduling or printing the to-do list |
| `CBS … Reboot required: no` | A component finished and does **not** need a reboot |
| `SYSPRP … (reboot requested)` | A module in the new OS "takes effect after reboot"; normal |
| `MIG Processing Registry: …Reboot Required` | Migrating a registry key whose name contains "Reboot" |
| `CBS Failed to set hint EAs from the catalog` | Info level; writing component cache hints |
| `WinSetupMon … GetNtPath … 0xC0000034`, `SETUPMON: Failed to install monitoring driver` | The setup monitor driver failed, often because TEMP points at a drive that does not exist in SafeOS. The log says "rollback will continue" — **not fatal**, but the TEMP setting is worth fixing |
| `pSPRemoveUpgradeRegTree … gle=0x00000005` | No permission to clear an old upgrade registry tree |
| `CSIAgent: Invalid xml format: "script" attribute is mandatory` | Migration XML format warning |
| `MIG Plugin … TableTextServiceMig`, `BRIDGEMIG`, `WinsockMig`, `adammigrate.dll … 0x80070002` | Migration plug-ins finding nothing to do |
| `PITR … not found`, `Failed to remove PITR snapshots` | The old OS does not have this component |
| `BFSVC: USE_EX_BINS flag is specified, but 2023 cert is not in db` | Secure Boot certificate status; does not affect the upgrade |
| `Action progress: [100%]` followed immediately by `[0%]` | **Progress is per step**, not overall |

## 5. Timeline of a normal upgrade

Order and timing observed in one successful silent ISO upgrade (`/dynamicupdate enable`, SSD system disk plus several hard disks). Use it to judge "where is it, how long left":

| Relative time | Log signature | Meaning |
|---|---|---|
| 0 min | `setup.exe`, `SetupPrep`, `SetupHost` start | |
| +1 min | `0x800705BB` etc., SetupHost gets a new PID | Relaunch after self-update |
| +1–2 min | `CompatData_*.xml` written | Compatibility scan done |
| +4–11 min | `FCDCATHelper: Transfer: [… %]` | Downloading Dynamic Update (several GB, depends on bandwidth) |
| +12–24 min | `DUImageSandbox`, `Expanding express MumX`, `DPX phase: Apply Deltas` | Expanding the cumulative update and integrating it into the new image |
| +31 min | `DUImage: Searching for driver updates` | Searching for driver updates |
| +32 min | Dozens of `Enqueue Operation`, `Add phase` 1–13 | Scheduling the install steps |
| +41 min | `Executing operation: Gather data, scope: EVERYTHING` | **Gathering data to migrate.** About 5 minutes normally; with an item explosion this becomes hours later in SafeOS |
| +46 min | `Register sync process`, `Backup the recovery partition` | Wrapping up |
| +47–80 min | `DPX`, `SXS Components preload`, `SYSPRP … Specialize_Offline` | Applying components, specialising the new OS |
| +88 min | `Ensure suspended services are stopped`, `Install Eula` | Last preparation before reboot |
| +89 min | **`Executing operation: Orchestrate OS switch`** | **Reboot warning.** In this case SetupHost exited two minutes later and the PC restarted |
| After reboot (SafeOS) | The same setupact.log keeps being written, system drive letter becomes e.g. F: | Back at the desktop, this log is in `C:\Windows\Panther\setupact.log` and can be replayed |
| After reboot (screen) | "Working on updates" 0–100%, 2–3 automatic restarts | About 10–15 minutes to the sign-in screen in this case; 30–60 minutes is a typical estimate, about 90 at most |

## 6. Designing monitor filters

Lessons from false alarms during real monitoring:

- Judge failures **only from Error-level lines with an error code** (`0xC19…`, `SetupHost::Execute … Result = 0x8…`) plus `Initiating rollback`. Matching words like rollback, fail or reboot produces a flood of false alarms
- Treat only `Executing operation:` lines for `Orchestrate OS switch` or `Prepare SafeOS` as reboot warnings
- Throttle progress events (e.g. at most every 5 minutes), otherwise there is an event every second
- Detect "log quiet too long" and "SetupHost gone", or a hang looks exactly like normal progress
- When SetupHost disappears, wait 60 seconds before concluding, because it briefly disappears during the self-update relaunch
