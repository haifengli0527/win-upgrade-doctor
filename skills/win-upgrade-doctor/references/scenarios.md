# Common upgrade scenarios and questions

Labels: **[observed]** comes from a real case; **[community]** is a common report from forums and users. The fixes generally work, but always check against the actual logs.

## Contents

1. Stuck: at a percentage, boot loops, black screen
2. Specific software and hardware
3. Choosing how to upgrade
4. Version questions
5. Remote or unattended upgrades
6. After the upgrade
7. Clean boot and retry order

## 1. Stuck

### Stuck at 20–30% (SafeOS) for hours [observed]

Do not force a restart yet. This stage migrates data, and its speed scales with **the number of items**, not their size.

- If you can get back into the old OS, count the items in `C:\Windows\SystemTemp`. Chrome and Edge updaters run as SYSTEM and leave large numbers of empty `*_url_fetcher_*` folders, possibly dozens a day and tens of thousands over a few years. They **ignore the TEMP environment variable**, because processes running as SYSTEM always use `C:\Windows\SystemTemp`
- Other common sources of item explosions [community]: `C:\Windows\Temp`, `C:\Windows\Logs\CBS`, `SoftwareDistribution\Download`, the print spooler, old Installer caches, a huge `$Recycle.Bin`
- Before clearing anything, confirm what it is (count, size, dates), close the related programs, and have the user run the deletion

### Stuck at 70–80% (first or second boot) [community]

Usually driver initialisation. If the disk light is blinking, keep waiting. Only consider a forced restart after 1–2 hours of no activity at all, then analyse the Rollback log after it rolls back.

### Boot loop, repeated rollbacks [community]

Usually 0x20017, 0x30018 or 0x40017: a driver crashing at boot. In order:

1. Unplug all peripherals except keyboard, mouse and display
2. Pause or remove filter drivers of third-party antivirus, encryption and backup software
3. Update storage controller drivers and BIOS
4. Disconnect unused disks

### Black screen with only a cursor [community]

Mostly a display driver problem (0x3000D type). Switch to integrated graphics or the basic display driver first, and reinstall after the upgrade.

## 2. Specific software and hardware

| Category | Why it is risky | Advice |
|---|---|---|
| Backup software (e.g. Acronis, with `file_protector`, `snapman`, `fltsrv`, `tib_mounter`) | File-system filter and snapshot drivers | **Pause real-time protection first**; fully remove only if the logs implicate it. In the observed case it worked fine throughout |
| Antivirus / EDR | Filter drivers incompatible with the new kernel; the classic 0x40017 cause | Pause or remove, reinstall the latest version afterwards |
| Third-party disk encryption | SafeOS cannot read the encrypted disk | Decrypt or suspend first; BitLocker is handled by setup automatically |
| RAM disk (SoftPerfect etc.) | Does not exist in SafeOS; TEMP pointing there breaks the setup monitor driver | Point TEMP and TMP back to C: before upgrading; afterwards **reboot to verify** the folders are recreated, then switch back |
| Virtual drives and adapters (VPN, Tailscale, VMs) | Extra drivers | Disconnect VPN for 0x800F0922; usually no need to remove |
| Intel RST / RAID | SafeOS needs the matching storage driver | Update the driver; prime suspect for 0x20017 |
| Several disks, several system partitions | Confuses partition analysis (0x…-0x20009) | Temporarily disconnect the old system disk |
| Engineering-sample or older CPUs | Hardware requirements check | Check `CompatData` for hard blocks; no block means no effect |

## 3. Choosing how to upgrade

### ISO setup.exe or Windows Update?

- Both use the same upgrade engine and fail for the same reasons. If Windows Update failed, an ISO usually fails too until the cause is removed
- **ISO suits**: going straight to a specific version, unattended runs (`/auto upgrade /quiet` reboots by itself), unreliable connections
- **Windows Update suits**: versions that differ only by an enablement package (e.g. 24H2→25H2→26H2), and staged-rollout protection
- Switching from Windows Update to an ISO: stop `UsoSvc`, `wuauserv` and `DoSvc`, end `MoUsoCoreWorker`, and check that `$WINDOWS.~BT` has not changed (preparation has not started)

### Why is it downloading when the ISO is mounted?

That is Dynamic Update: the latest cumulative update, setup fixes, compatibility data and drivers. `/dynamicupdate disable` skips it, but then run Windows Update after the upgrade.

### Do I need to download SetupDiag first?

Not necessarily. The Rollback log usually already has the result and extend code, and setup runs SetupDiag itself on failure (results in `C:\Windows\Logs\SetupDiag\`). Download it when the logs are gone or for cross-checking.

## 4. Version questions

### How 24H2, 25H2 and 26H2 relate

They share one kernel generation (builds 261xx–263xx). Moving between them only needs an **enablement package**: minutes and one reboot. The real work is a full upgrade from an **older generation** (e.g. 23H2's 22631, or Windows 10). Seeing `26100.xxxx` in the log does not mean the ISO is wrong; it is the shared kernel version.

### I want 26H2 but Windows Update only offers 25H2

26H2 rolls out in stages. Upgrade to 25H2 and apply the 26H2 enablement package later with the same result, or use a 26H2 ISO directly.

### New versions let you name the user folder — does an upgrade allow that?

No. From 2026, **clean installs** of 24H2/25H2 and later let you choose `C:\Users\<name>` during OOBE. An upgrade keeps the existing account and folder, never shows that screen, and cannot break because of it. To get a new folder name:

- Clean install
- Or create a new local account with the desired name and move the data over

Renaming the folder and editing `ProfileImagePath` by hand is **not recommended**; many programs hard-code the old path.

### Was this PC installed clean or upgraded from Windows 10?

Look at the `HKLM\SYSTEM\Setup\Source OS (Updated on …)` keys. Each full upgrade leaves one, and the `CurrentBuild` of the oldest is the earliest version (10240–19045 is Windows 10, 22000 and up is Windows 11). Note: `ProductName` in the registry often says "Windows 10" on Windows 11; this is a known quirk, do not rely on it.

## 5. Remote or unattended upgrades

- When the user is away, use `setup.exe /auto upgrade /quiet /eula accept`: no buttons to click. Windows Update stops at "Restart required" and waits for someone
- Check that the power plan will not sleep (`powercfg /requests` shows SetupHost requesting the system stay awake)
- The only reboot warning is `Orchestrate OS switch`, usually less than two minutes ahead
- Claude goes offline at the reboot; post-upgrade checks happen only once the user is back at the desktop and starts Claude again
- Push notifications need mobile push enabled in the user's settings; otherwise only chat messages reach them

## 6. After the upgrade

| Symptom | Assessment |
|---|---|
| `Windows.old` takes tens of GB | Normal; allows going back for about 10 days |
| RAM disk TEMP folders gone [observed] | The upgrade may have lost the RAM disk software's settings. Reconfigure folder creation at boot, then reboot to verify |
| DNS Client "name resolution policy table has been corrupted" (1023) at boot, rule DNS server 100.100.100.100 [observed] | NRPT rule written by Tailscale racing the DNS client at boot. Nothing to do if DNS works |
| `luafv` service blocked from loading (7000) [observed] | File virtualization for legacy apps; little effect on normal use. Whether this is general on new releases needs verification |
| Some old drivers or software need reinstalling | Get versions that support the new release from the vendor |
| Privacy settings, welcome screens | Normal OOBE |

## 7. Clean boot and retry order

Cheapest first. Retry after each step so the real cause is easier to identify:

1. Fix what the log points at directly (item explosions, low disk space)
2. Point TEMP and TMP back to C:, unplug unneeded peripherals and disks
3. Pause real-time protection of third-party antivirus, backup and encryption software
4. Clean boot (`msconfig`: hide Microsoft services, disable the rest, disable startup items)
5. Update BIOS, storage drivers and display drivers
6. Fully remove the suspect software (vendors usually provide a cleanup tool)
7. Only then consider a clean install
