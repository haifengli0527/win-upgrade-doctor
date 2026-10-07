"""Repository checks for win-upgrade-doctor. Standard library only.

Run: python tests/run_tests.py
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKILL = ROOT / "skills" / "win-upgrade-doctor"
ZH = ROOT / "docs" / "zh-TW"
failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


def frontmatter(path):
    text = path.read_text(encoding="utf-8")
    m = re.match(r"^---\r?\n(.*?)\r?\n---\r?\n", text, re.S)
    if not m:
        return None
    fields = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            fields[k.strip()] = v.strip()
    return fields


# 1. Skill frontmatter
for path in (SKILL / "SKILL.md", ZH / "SKILL.md"):
    fm = frontmatter(path)
    check(fm is not None, f"{path.relative_to(ROOT)}: missing YAML frontmatter")
    if fm:
        check(fm.get("name") == "win-upgrade-doctor", f"{path.relative_to(ROOT)}: name must be win-upgrade-doctor")
        desc = fm.get("description", "")
        check(50 < len(desc) <= 1024, f"{path.relative_to(ROOT)}: description length {len(desc)} not in 51..1024")

# 2. English and Chinese references mirror each other
en_refs = sorted(p.name for p in (SKILL / "references").glob("*.md"))
zh_refs = sorted(p.name for p in (ZH / "references").glob("*.md"))
check(en_refs == zh_refs, f"reference files differ: en={en_refs} zh={zh_refs}")
for name in ("error-codes.md", "log-guide.md", "scenarios.md", "case-study.md"):
    check(name in en_refs, f"missing reference {name}")

# 3. Relative links resolve
link_re = re.compile(r"\]\(([^)#\s]+)(?:#[^)]*)?\)")
for md in ROOT.rglob("*.md"):
    if ".git" in md.parts:
        continue
    for target in link_re.findall(md.read_text(encoding="utf-8")):
        if re.match(r"^[a-z]+://", target) or target.startswith("mailto:"):
            continue
        check((md.parent / target).resolve().exists(), f"{md.relative_to(ROOT)}: broken link {target}")

# 4. Scripts are ASCII-only (Windows PowerShell 5.1 reads BOM-less files as ANSI)
scripts = sorted((SKILL / "scripts").glob("*.ps1"))
check(len(scripts) == 4, f"expected 4 scripts, found {len(scripts)}")
for ps in scripts + [ROOT / "tests" / "test_scripts.ps1"]:
    data = ps.read_bytes()
    bad = [i for i, b in enumerate(data) if b > 127]
    check(not bad, f"{ps.relative_to(ROOT)}: non-ASCII byte at offset {bad[:1]}")

# 4b. Scripts must stay read-only: no state-changing cmdlets outside comments/strings shown to the user
mutating = re.compile(r"^\s*(?!#)(.*\b(Remove-Item|Set-ItemProperty|New-ItemProperty|Stop-Service|Set-Service|Stop-Process|Clear-Content|Set-Content|reg(\.exe)?\s+(add|delete))\b)", re.I)
for ps in scripts:
    for n, line in enumerate(ps.read_text(encoding="ascii", errors="replace").splitlines(), 1):
        m = mutating.match(line)
        if m and "Out-Item" not in line:  # suggestions printed for the user are allowed
            failures.append(f"{ps.relative_to(ROOT)}:{n}: state-changing command in a read-only script")

# 5. No personal data or real logs
sensitive = [
    (re.compile(r"[A-Za-z0-9._%+-]+@(?!users\.noreply\.github\.com)[A-Za-z0-9.-]+\.[a-z]{2,}"), "e-mail address"),
    (re.compile(r"C:\\\\?Users\\\\?(?!<|%|\.\.\.|user\b|User\b|\*)[A-Za-z0-9_.-]+", re.I), "real user profile path"),
    (re.compile(r"\b[a-z0-9-]+\.ts\.net\b"), "tailnet name"),
    (re.compile(r"gh[pousr]_[A-Za-z0-9]{20,}"), "GitHub token"),
    (re.compile(r"\b[A-Z0-9]{5}(-[A-Z0-9]{5}){4}\b"), "product key"),
]
text_ext = {".md", ".ps1", ".py", ".json", ".yml", ".yaml", ".log", ".txt"}
for f in ROOT.rglob("*"):
    if not f.is_file() or ".git" in f.parts or f.suffix.lower() not in text_ext:
        continue
    text = f.read_text(encoding="utf-8", errors="replace")
    for rx, what in sensitive:
        for m in rx.finditer(text):
            if "example" in m.group(0).lower():
                continue
            failures.append(f"{f.relative_to(ROOT)}: possible {what}: {m.group(0)}")
for f in ROOT.rglob("*"):
    if f.is_file() and f.suffix.lower() in {".raw", ".evtx", ".dmp", ".etl"}:
        failures.append(f"{f.relative_to(ROOT)}: real log/dump file must not be committed")

# 6. Fixtures are synthetic (dated 2026-01-0x by convention)
for log in (ROOT / "tests" / "fixtures").rglob("*.log"):
    for n, line in enumerate(log.read_text(encoding="utf-8").splitlines(), 1):
        if re.match(r"^\d{4}-\d\d-\d\d ", line) and not line.startswith("2026-01-0"):
            failures.append(f"{log.relative_to(ROOT)}:{n}: fixture lines must use synthetic dates 2026-01-0x")
            break

# 7. Plugin metadata consistent
plugin = json.loads((ROOT / ".claude-plugin" / "plugin.json").read_text(encoding="utf-8"))
market = json.loads((ROOT / ".claude-plugin" / "marketplace.json").read_text(encoding="utf-8"))
check(plugin["name"] == "win-upgrade-doctor", "plugin.json name")
check(market["plugins"][0]["name"] == plugin["name"], "marketplace plugin name mismatch")
check(market["plugins"][0].get("version") == plugin["version"], "marketplace/plugin version mismatch")
changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
check(f"## {plugin['version']}" in changelog, f"CHANGELOG has no entry for {plugin['version']}")

# 8. README essentials
for readme in ("README.md", "README.zh-TW.md"):
    text = (ROOT / readme).read_text(encoding="utf-8")
    for needle in ("/plugin marketplace add haifengli0527/win-upgrade-doctor", "LICENSE", "preflight.ps1", "diagnose.ps1"):
        check(needle in text, f"{readme}: missing '{needle}'")

if failures:
    print(f"FAIL ({len(failures)})")
    for f in failures:
        print("  - " + f)
    sys.exit(1)
print("OK: all repository checks passed")
