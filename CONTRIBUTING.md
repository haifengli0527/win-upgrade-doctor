# Contributing

## Most useful: log excerpts from real upgrades

Open an issue with the template. Include:

- The result and extend code (`Reporting post reboot event -> [...]` in `$WINDOWS.~BT\Sources\Rollback\setupact.log`)
- The output of `diagnose.ps1`
- The last ~50 lines of `setupact.log` before the failure or hang
- Any message the scripts misreport (false alarm or missed warning)

**Redact before posting**: user names (paths like `C:\Users\<name>`), computer name, domain, network or tailnet names, e-mail addresses, product keys, licence blobs.

Never add real logs to `tests/fixtures/`. Fixtures are **synthetic**: write lines in the same format with made-up values.

## Running the tests

Repository checks (any OS, Python 3.10+, standard library only):

```bash
python tests/run_tests.py
git diff --check
```

Script behaviour (Windows, PowerShell 5.1 or 7):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test_scripts.ps1
```

## Rules

- Scripts stay **read-only**: no deletions, no service, registry or environment changes. Suggest commands for the user to run instead
- Scripts stay **ASCII-only**: Windows PowerShell 5.1 reads BOM-less files with the ANSI code page, so non-ASCII text breaks on many locales
- No third-party dependencies (no Pester, no pip packages)
- If you change filter rules in `watch.ps1`, add the triggering line to a fixture and a check to `tests/test_scripts.ps1`
- Keep `skills/` (English) and `docs/zh-TW/` (Traditional Chinese) in sync; if you can only write one, say so in the PR

## PR checklist

- [ ] `python tests/run_tests.py` passes
- [ ] `tests\test_scripts.ps1` passes (or explain why you could not run it)
- [ ] `git diff --check` is clean
- [ ] No real logs, user names or machine names added
- [ ] English and Chinese docs updated, or the gap noted
