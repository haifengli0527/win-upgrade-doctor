# Changelog

## 0.1.0 — 2026-10-07

First public version, built from one real 23H2 → 26H2 upgrade (one failure, one success) plus Microsoft's error-code documentation.

- Skill `win-upgrade-doctor` (English) with references: error codes, log guide, scenarios, case study
- Traditional Chinese translation under `docs/zh-TW/`
- Read-only PowerShell scripts: `preflight.ps1`, `watch.ps1` (with `-Replay`), `diagnose.ps1` (with `-SourcesDir`), `postcheck.ps1`
- Synthetic log fixtures and tests (Python stdlib for repository checks, PowerShell for script behaviour)
