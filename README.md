# win-upgrade-doctor

**A [Claude Code](https://docs.claude.com/claude-code) skill and standalone PowerShell toolkit for Windows feature upgrades: pre-flight checks, live log monitoring, failure diagnosis and post-upgrade verification.**

[繁體中文說明 → README.zh-TW.md](README.zh-TW.md)

> **Not an official Microsoft tool.** It reads logs and system state and changes nothing by itself (apart from mounting an ISO you point it at), but an in-place upgrade touches the whole PC. **Back up first.** Use at your own risk (see [LICENSE](LICENSE)).

---

## The story: "stuck at 28%" for six hours

A Windows 11 23H2 → 26H2 upgrade kept failing with `0xC1900101`. The last attempt sat at **"Working on updates 28%" for hours** until it was force-restarted. The obvious suspect was the backup software's kernel drivers ("0xC1900101 is a driver problem").

The logs said otherwise:

| What the logs showed | Meaning |
|---|---|
| `Reporting post reboot event -> [0xC1900101, 0x2000D]` | SAFE_OS phase, **MIGRATE_DATA** |
| `Current bugcheck string: NULL`, `No crash detected` | **No driver crash at all** |
| Thousands of `MIG Processing File: C:\Windows\SystemTemp\msedge_url_fetcher_…` at ~0.5–1 s each | Setup was migrating junk, one item at a time |
| `C:\Windows\SystemTemp`: **31,959 items**, 31,451 of them empty `chrome_url_fetcher_*` / `msedge_url_fetcher_*` folders | 3 years of leftovers from Chromium-based browser updaters |

31,000 items × 0.5–1 s ≈ 4–8 hours. It was not hung; it was slow, and the forced restart caused the rollback. After deleting the empty folders, the same step took **5 minutes** and the upgrade succeeded. The backup software stayed installed.

The empty-folder buildup is a [known Chromium issue](https://issues.chromium.org/issues/40283581) ([Brave users report 800–1000 a week](https://github.com/brave/brave-browser/issues/46202)), but it is rarely connected to upgrade failures. Because these folders hold no data they waste no disk space, so nobody notices them until an upgrade has to process every one. Full write-up: [case study](skills/win-upgrade-doctor/references/case-study.md).

## What's inside

| Part | What it does |
|---|---|
| [`skills/win-upgrade-doctor/SKILL.md`](skills/win-upgrade-doctor/SKILL.md) | Workflow for Claude: which phase the user is in, an order of reasoning that avoids jumping to conclusions, confidence labels, safety and consent rules |
| [`references/error-codes.md`](skills/win-upgrade-doctor/references/error-codes.md) | Phase and operation tables, common `0xC1900101-0x…` and `0x800…` combinations, MOSETUP codes |
| [`references/log-guide.md`](skills/win-upgrade-doctor/references/log-guide.md) | Where the logs are, real warning signs, **20+ harmless messages that look like errors**, the timeline of a real upgrade |
| [`references/scenarios.md`](skills/win-upgrade-doctor/references/scenarios.md) | Stuck at %, boot loops, specific software (backup, AV, encryption, RAM disk, RST), ISO vs Windows Update, 24H2/25H2/26H2, unattended upgrades, after-upgrade quirks |
| [`scripts/preflight.ps1`](skills/win-upgrade-doctor/scripts/preflight.ps1) | Pre-upgrade check: SystemTemp item count with an extra-time estimate, TEMP/TMP on RAM disks, third-party filter drivers, disk space, pending reboot, EFI partitions, ISO edition/language match |
| [`scripts/watch.ps1`](skills/win-upgrade-doctor/scripts/watch.ps1) | Live monitor that prints only events worth reporting, with about 2 minutes' warning before the reboot. `-Replay` runs it over a finished log |
| [`scripts/diagnose.ps1`](skills/win-upgrade-doctor/scripts/diagnose.ps1) | Post-failure: decodes the extend code, crash or no crash, what setup was doing last and how fast, whether suspects appear in Error lines |
| [`scripts/postcheck.ps1`](skills/win-upgrade-doctor/scripts/postcheck.ps1) | After the upgrade: version, activation, devices, drivers, boot errors, TEMP folders, Windows.old |

All scripts are **read-only** (the one exception: `preflight.ps1 -IsoPath` mounts the ISO and leaves it mounted for setup.exe), ASCII-only, and run on Windows PowerShell 5.1 or PowerShell 7.

## Install (Claude Code)

As a plugin:

```
/plugin marketplace add haifengli0527/win-upgrade-doctor
/plugin install win-upgrade-doctor@win-upgrade-doctor
```

Or copy [`skills/win-upgrade-doctor`](skills/win-upgrade-doctor) to `~/.claude/skills/`.

Then just describe the problem: *"my Windows 11 upgrade fails with 0xC1900101"*, *"it's been at 28% for three hours"*, *"check whether this PC is ready for 26H2"*. Claude replies in your language.

## Use the scripts without Claude

From an elevated PowerShell:

```powershell
cd skills\win-upgrade-doctor\scripts

# Before upgrading (optionally check an ISO)
powershell -NoProfile -ExecutionPolicy Bypass -File .\preflight.ps1 -IsoPath D:\Win11.iso

# While setup.exe is running (Ctrl+C to stop)
powershell -NoProfile -ExecutionPolicy Bypass -File .\watch.ps1

# After a rollback (optionally name suspects)
powershell -NoProfile -ExecutionPolicy Bypass -File .\diagnose.ps1 -Suspects snapman,file_protector

# After a successful upgrade
powershell -NoProfile -ExecutionPolicy Bypass -File .\postcheck.ps1
```

## Honest limitations

- **Built from one real case plus documentation.** The harmless-message list and the timeline come from one successful upgrade and one failure. Other machines will produce other noise; please report it.
- **Nothing can watch SafeOS, first boot or OOBE.** No third-party code runs there, so monitoring stops at the first reboot, and so does Claude. You get a warning before it, and diagnosis afterwards.
- **`diagnose.ps1` has been tested on synthetic failure logs only.** The real failing machine's logs were overwritten by the successful retry. Real rollback logs (redacted) are very welcome.
- **Microsoft does not publish a log format.** Message text can change between releases.
- Error-code descriptions are paraphrased from Microsoft Learn with links; the log always wins.

## Contributing

Bug reports with log excerpts are the most useful contribution. **Redact first**: user names, computer names, domain and network names, e-mail addresses, product keys. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to run the tests (no third-party dependencies).

## License

[MIT](LICENSE)
