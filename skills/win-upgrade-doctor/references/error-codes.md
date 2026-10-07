# Upgrade error code reference

Source: Microsoft Learn, "Windows 10 upgrade error codes" and "Windows 10 upgrade resolution procedures" (Windows 11 uses the same mechanism). The descriptions below are summarised and paraphrased. Microsoft notes that extend codes can change between releases, so the log text always wins.

- https://learn.microsoft.com/troubleshoot/windows-client/setup-upgrade-and-drivers/windows-10-upgrade-error-codes
- https://learn.microsoft.com/troubleshoot/windows-client/setup-upgrade-and-drivers/windows-10-upgrade-resolution-procedures

## Contents

1. How the codes are built
2. Extend code: phase and operation
3. Common 0xC1900101 combinations
4. Common 0x800xxxxx combinations
5. Compatibility and setup (MOSETUP) codes
6. Other common codes

## 1. How the codes are built

A failure gives two codes: **result code - extend code**, e.g. `0xC1900101 - 0x4000D`.

- Result code starting `0x8` is a Win32 error (look up the last four hex digits, e.g. `0x80070070` → `0x70` = ERROR_DISK_FULL)
- Result code starting `0xC` is an NTSTATUS / setup-specific code
- Extend code: **first digit = phase, last two digits = operation** (`0x4000D` = phase 4, operation 0D)
- Only a result code and no extend code: the tool (e.g. Windows Update UI) did not capture it. Look in the Rollback log for `Reporting post reboot event -> [result, extend]`
- **`0xC1900108` (MOSETUP_E_REPORTING) is only a remap for telemetry.** The log says `Remapping install error [0xC1900101] -> [0xC1900108] for telemetry`; the real error is the first one

## 2. Extend code: phase and operation

### Phase

| Code | Phase | Plain meaning | What the user sees |
|---|---|---|---|
| 0 | UNKNOWN | Unknown | |
| 1 | DOWNLEVEL | Still preparing inside the old OS | Setup window on the desktop, or background |
| 2 | SAFE_OS | Rebooted into a temporary minimal OS; applying the new OS and migrating data | "Working on updates" roughly 0–30% |
| 3 | FIRST_BOOT | First boot into the new OS; drivers and features | roughly 30–75% |
| 4 | OOBE_BOOT (often called SECOND_BOOT) | Second boot; settings and user data | roughly 75–100% |
| 5 | UNINSTALL | Rollback / uninstall | "Restoring your previous version of Windows" |

The percentage-to-phase mapping is empirical and varies between releases.

### Operation

| Code | Operation | Code | Operation |
|---|---|---|---|
| 0 | UNKNOWN | 10 | ADD_DRIVER |
| 1 | COPY_PAYLOAD | 11 | ENABLE_FEATURE |
| 2 | DOWNLOAD_UPDATES | 12 | DISABLE_FEATURE |
| 3 | INSTALL_UPDATES | 13 | REGISTER_ASYNC_PROCESS |
| 4 | INSTALL_RECOVERY_ENVIRONMENT | 14 | REGISTER_SYNC_PROCESS |
| 5 | INSTALL_RECOVERY_IMAGE | 15 | CREATE_FILE |
| 6 | REPLICATE_OC | 16 | CREATE_REGISTRY |
| 7 | INSTALL_DRIVERS | 17 | BOOT |
| 8 | PREPARE_SAFE_OS | 18 | SYSPREP |
| 9 | PREPARE_ROLLBACK | 19 | OOBE |
| A | PREPARE_FIRST_BOOT | 1A / 1B | BEGIN / END_FIRST_BOOT |
| B | PREPARE_OOBE_BOOT | 1C / 1D | BEGIN / END_OOBE_BOOT |
| C | APPLY_IMAGE | 1E | PRE_OOBE |
| D | MIGRATE_DATA | 1F | POST_OOBE |
| E | SET_PRODUCT_KEY | 20 | ADD_PROVISIONING_PACKAGE |
| F | ADD_UNATTEND | | |

## 3. Common 0xC1900101 combinations

`0xC1900101` on its own only means "a rollback happened". Microsoft says the usual cause is an incompatible driver, but **do not conclude that from this sentence alone**: force-restarting during the upgrade also produces 0xC1900101, with no crash recorded anywhere.

| Extend | Phase / operation | Common causes | Suggested actions |
|---|---|---|---|
| 0x20004 | SAFE_OS / install recovery environment | Outdated drivers, unused SATA devices, antivirus | Update BIOS and drivers, remove unused disks and devices, temporarily remove third-party antivirus |
| 0x2000C | SAFE_OS / apply image | Outdated drivers, disk or file-system corruption, corrupt ISO | `chkdsk`, unplug peripherals, re-download the ISO, enable dynamic update |
| **0x2000D** | SAFE_OS / migrate data | **So many items to migrate that it is extremely slow and the user force-restarts**; or a file/driver that cannot be migrated | Look at what it was migrating last. Masses of repeated items → clear the source and retry (see case study) |
| 0x20017 | SAFE_OS / boot | Driver failure when booting SafeOS: storage controllers (Intel RST, NVMe), third-party disk encryption, BIOS/TPM settings, hardware fault | Update storage drivers and BIOS, suspend third-party encryption, unplug extra disks; find the driver in setupact.log |
| 0x30018 | FIRST_BOOT / sysprep | A device driver stopped responding on first boot: antivirus/EDR filters, network/Wi-Fi, graphics | Unplug peripherals, update drivers, read `Rollback\setupapi\setupapi.dev.log` |
| 0x3000D | FIRST_BOOT / migrate data | Display driver | Update or temporarily remove the display driver |
| 0x4000D | OOBE_BOOT / migrate data | Driver configuration problem, damaged user profile | Look for `Crash 0x… detected` and bugcheck parameters in the Rollback log, check `setupmem.dmp` |
| 0x40017 | OOBE_BOOT / boot | Driver failure on second boot, **typically antivirus or encryption filter drivers** | Clean boot; pause or remove filter drivers from antivirus/encryption/backup software |
| 0x4001E | OOBE_BOOT / pre-OOBE | Generic error before OOBE | General troubleshooting |

## 4. Common 0x800xxxxx combinations

| Code | Meaning | Suggested actions |
|---|---|---|
| 0x8007042B - 0x4000D | A process ended unexpectedly while migrating data on second boot | Find the file, app or driver that cannot be migrated in the logs |
| 0x8007001F - 0x3000D | Data migration failed on first boot, often user-profile related | Check `ProfileList` in the registry for leftovers of deleted accounts and invalid profiles under `\Users` |
| 0x8007001F - 0x4000D | A device is not functioning | Find, unplug, update or replace the device |
| 0x80070005 - 0x4000D | Access denied while migrating data | Find the item reporting access denied in the logs |
| 0x80073BC3 / 0x80070002 / 0x80073B92 - 0x20009 | Partition analysis failed, often **multiple system partitions on different disks** (old system disk still attached) | Temporarily disconnect the disk with the old system partition |
| 0x800704B8 - 0x3001A | Extended error on first boot | Disable third-party antivirus, unplug devices, clean boot |
| 0x80070003 / 0x80070490 / 0x80040005 - 0x20007 | Driver installation failed in SafeOS | Find the problem driver |
| 0x8007025D - 0x2000C | Corrupt ISO metadata, or bad blocks in RAM or storage media | Re-download the ISO, test memory |
| 0x80070070 / 0xC190020E | Not enough space | Free space on C: (20 GB minimum for 64-bit; 40 GB+ recommended in practice) |
| 0x80070020 | File in use by another process | Clean boot and retry |
| 0x80070522 | Insufficient privilege | Run as Administrator |
| 0x800F0922 | Commonly EFI system / recovery partition too small, or VPN interference | Check partition sizes, disconnect VPN (not in the Microsoft table; community experience) |

## 5. Compatibility and setup (MOSETUP) codes

| Code | Meaning | What to do |
|---|---|---|
| 0xC1900107 | Cleanup from a previous attempt is pending | Reboot; if that fails, Disk Cleanup → Clean up system files |
| 0xC1900200 / 0xC1900201 / 0xC1900202 | Minimum hardware requirements not met | Check TPM 2.0, Secure Boot, supported CPU list |
| 0xC1900204 | The chosen migration is not available (e.g. edition or language mismatch, cannot keep files) | ISO edition, language and architecture must match the running system |
| 0xC1900208 / 0xC1900209 | An incompatible app blocks the upgrade | See `BlockingType="Hard"` entries in `Panther\CompatData_*.xml` |
| 0xC1900216 | A rollback is pending | Let the rollback finish and reboot |
| 0xC1900129 | A newer version of setup will continue the installation | **Normal**; wait for the relaunch |
| 0xC19001E1 | The setup process was suspended | Check whether something suspended SetupHost |
| 0xC190011F / 0xC1900405 | The setup process crashed | Read setuperr.log around that time |

## 6. Other common codes

| Code | Meaning |
|---|---|
| 0x800705BB, 0x800704D3 (right after starting setup) | Usually accompanies setup relaunching after a self-update; check whether SetupHost has a new PID and keeps writing the log |
| 0x80240017 | Upgrade not available for this edition, possibly blocked by policy |
| 0x80244018 | Download failed through a proxy |
| 0x80190001 / 0x80246007 | Download failed; use an ISO or the Media Creation Tool |
| 0xC1800118 | WSUS content missing its decryption key (enterprise) |
