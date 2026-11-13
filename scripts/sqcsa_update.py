#!/usr/bin/env python3
"""
sqcsa_update.py — Security and Quality Code Static Analysis updater.

Usage:
    python3 scripts/sqcsa_update.py <rel-folder> [<rel-folder> ...]

Each <rel-folder> is a path relative to the project root, e.g.:
    src/common/scalar
    verify

For each folder the script runs:
    1. flawfinder --minlevel=4 --quiet
    2. cppcheck --std=c99 --enable=warning,portability --quiet
    3. clang --analyze -std=c99

It then rewrites the matching "── sec-<name>  (<folder>/)" block inside
doc/txt/SQCSA.txt, or appends a new block when none exists, and updates the
summary table row for that target.

Run from anywhere:
    python3 scripts/sqcsa_update.py src/common/scalar verify
"""

import argparse
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SQCSA = ROOT / "doc" / "txt" / "SQCSA.txt"

ALWAYS_INCLUDES = ["-Iinclude"]
INCLUDE_EXTRAS = {
    "verify": [],
    "src/common/scalar": [],
}

# Files passed instead of the directory, so build/ and verify/.cache
# are not translation units.
FILE_LISTS = {
    "verify": ["verify/suite/test_host.c", "verify/suite/test_mem.c"],
}

SEC_CFLAGS = [
    "-std=c99",
    "-Wall",
    "-Wextra",
    "-Wformat=2",
    "-fno-strict-aliasing",
    "-fno-builtin",
]

CLANG_SKIP_SUBDIRS = {}
CLANG_SKIP_ENTIRELY = set()

CPP_DIAG = re.compile(
    r":(\d+):(?:\d+:)?\s*(error|warning|portability|style):"
)


def run(cmd, cwd=None):
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)
    return r.stdout, r.stderr, r.returncode


def folder_key(folder):
    return Path(folder).name


def sec_target_name(folder):
    return f"sec-{folder_key(folder)}"


def targets_for(folder):
    if folder in FILE_LISTS:
        return [str(ROOT / rel) for rel in FILE_LISTS[folder]]
    return [str(ROOT / folder) + "/"]


def run_flawfinder(folder):
    stdout, _, _ = run(
        ["flawfinder", "--minlevel=4", "--quiet", *targets_for(folder)],
        cwd=ROOT,
    )
    stdout_full, _, _ = run(
        ["flawfinder", "--minlevel=4", *targets_for(folder)],
        cwd=ROOT,
    )

    findings = []
    hit_re = re.compile(r"^.+:\d+:\s*\[\d+\]")
    for line in stdout.splitlines():
        line = line.strip().replace(str(ROOT) + "/", "")
        if hit_re.match(line):
            findings.append(line)

    lines_analyzed = 0
    hits_4plus = 0
    hits_5plus = 0
    for line in stdout_full.splitlines():
        m = re.search(r"Lines analyzed\s*[:=]\s*([\d,]+)", line)
        if m:
            lines_analyzed = int(m.group(1).replace(",", ""))
        m = re.search(r"Hits@level\+\s*=.*?\[4\+\]\s*([\d]+)", line)
        if m:
            hits_4plus = int(m.group(1))
        m = re.search(r"Hits@level\+\s*=.*?\[5\+\]\s*([\d]+)", line)
        if m:
            hits_5plus = int(m.group(1))

    return dict(
        lines_analyzed=lines_analyzed,
        hits_4plus=hits_4plus,
        hits_5plus=hits_5plus,
        findings=findings,
    )


def run_cppcheck(folder):
    includes = ALWAYS_INCLUDES + INCLUDE_EXTRAS.get(folder, [])
    cmd = (
        ["cppcheck", "--std=c99", "--enable=warning,portability", "--quiet"]
        + includes
        + targets_for(folder)
    )
    stdout, stderr, _ = run(cmd, cwd=ROOT)
    findings = []
    for line in (stdout + "\n" + stderr).splitlines():
        line = line.strip().replace(str(ROOT) + "/", "")
        if line and CPP_DIAG.search(line) and "unhandledChar" not in line:
            findings.append(line)
    return dict(findings=findings, total=len(findings))


def run_clang_analyze(folder):
    if folder in CLANG_SKIP_ENTIRELY:
        return dict(skipped=True, skip_reason="clang --analyze skipped", warnings=[], total=0)

    skip_subdirs = CLANG_SKIP_SUBDIRS.get(folder, [])
    if folder in FILE_LISTS:
        c_files = [ROOT / rel for rel in FILE_LISTS[folder]]
    else:
        c_files = []
        folder_path = ROOT / folder
        for f in sorted(folder_path.rglob("*.c")):
            rel = f.relative_to(folder_path)
            if skip_subdirs and rel.parts and rel.parts[0] in skip_subdirs:
                continue
            c_files.append(f)

    if not c_files:
        return dict(skipped=False, skip_reason="", warnings=[], total=0)

    includes = ALWAYS_INCLUDES + INCLUDE_EXTRAS.get(folder, [])
    cmd = (
        ["clang", "--analyze"]
        + SEC_CFLAGS
        + includes
        + ["-Xanalyzer", "-analyzer-output=text"]
        + [str(f) for f in c_files]
    )
    stdout, stderr, _ = run(cmd, cwd=ROOT)
    warnings = []
    for line in (stdout + stderr).splitlines():
        if "warning:" in line or "error:" in line:
            warnings.append(line.replace(str(ROOT) + "/", "").strip())

    skip_note = ""
    if skip_subdirs:
        skip_note = "clang --analyze skipped " + ", ".join(skip_subdirs)
    return dict(skipped=False, skip_reason=skip_note, warnings=warnings, total=len(warnings))


def build_section(folder, fw, cpp, clang):
    target = sec_target_name(folder)
    today = date.today().isoformat()
    bar = "─" * max(0, 68 - len(folder) - len(today))
    lines = [f"  ── {target}  ({folder}/)  —  updated {today}  {bar}", ""]

    if clang["skipped"]:
        lines.append(f"  clang --analyze is not run on {folder}/.")
        lines.append("  " + clang["skip_reason"])
        lines.append("  flawfinder and cppcheck cover the directory.")
    else:
        lines.append(f"  clang --analyze  {folder}")
        if clang["skip_reason"]:
            lines.append("  " + clang["skip_reason"])
        if clang["warnings"]:
            for w in clang["warnings"][:20]:
                lines.append(f"    {w}")
            if len(clang["warnings"]) > 20:
                lines.append(f"    ... ({len(clang['warnings']) - 20} more)")
        else:
            lines.append("    (no diagnostics)")
    lines.append("")

    lines.append(f"  flawfinder --minlevel=4  {folder}/")
    lines.append(f"    Lines analyzed : {fw['lines_analyzed']:,}")
    level5 = "   (zero at level 5)" if fw["hits_5plus"] == 0 else f"   ({fw['hits_5plus']} at level 5)"
    lines.append(f"    Hits@level 4   : {fw['hits_4plus']}{level5}")
    lines.append(f"    Hits@level 4+  : {fw['hits_4plus']}")
    if fw["hits_4plus"] == 0:
        lines.append(f"  Clean at level 4.  {folder}/ passes the flawfinder gate today.")
    else:
        for hit in fw["findings"][:12]:
            lines.append("    " + hit.replace(str(ROOT) + "/", ""))
        if len(fw["findings"]) > 12:
            lines.append(f"    ... ({len(fw['findings']) - 12} more)")
    lines.append("")

    lines.append(f"  cppcheck  {folder}/")
    if cpp["findings"]:
        for f in cpp["findings"][:30]:
            lines.append(f"    {f}")
        if len(cpp["findings"]) > 30:
            lines.append(f"    ... ({len(cpp['findings']) - 30} more findings)")
    else:
        lines.append("    (no findings)")
    lines.append("")
    return "\n".join(lines)


def gate_status(fw, cpp, clang):
    if fw["hits_4plus"] == 0 and cpp["total"] == 0 and clang["total"] == 0:
        return "PASS"
    return "INFO"


def summary_row(folder, fw, cpp, clang):
    target = sec_target_name(folder)
    fw_col = str(fw["hits_4plus"])
    cpp_col = str(cpp["total"])
    clang_col = "n/a" if clang["skipped"] else str(clang["total"])
    gate = gate_status(fw, cpp, clang)
    return f"    {target:<12} {fw_col:>13}  {cpp_col:>17}  {clang_col:>14}  {gate}"


def patch_sqcsa(folder, section_text, row_text, sqcsa_path):
    content = sqcsa_path.read_text(encoding="utf-8")
    target = sec_target_name(folder)

    section_pattern = re.compile(
        r"  ── " + re.escape(target) + r"\s+\([^)]+\)[^\n]*\n"
        r".*?"
        r"(?=\n  ── (?:sec-|Summary)|\Z)",
        re.DOTALL,
    )
    if section_pattern.search(content):
        content = section_pattern.sub(section_text.rstrip("\n") + "\n", content, count=1)
    else:
        summary_anchor = "  ── Summary table"
        if summary_anchor in content:
            content = content.replace(summary_anchor, section_text + "\n" + summary_anchor, 1)
        else:
            content = content.rstrip("\n") + "\n\n" + section_text

    # Only the summary table. A prose mention of "sec-scalar" is not a row.
    marker = "  ── Summary table"
    if marker in content:
        head, tail = content.split(marker, 1)
        row_pattern = re.compile(
            r"^    " + re.escape(target) + r"\s+.*$",
            re.MULTILINE,
        )
        if row_pattern.search(tail):
            tail = row_pattern.sub(row_text, tail, count=1)
        else:
            gate_at = tail.find("\n  Gate = ")
            if gate_at == -1:
                tail = tail.rstrip("\n") + "\n" + row_text + "\n"
            else:
                tail = tail[:gate_at] + "\n" + row_text + tail[gate_at:]
        content = head + marker + tail
    else:
        content = content.rstrip("\n") + "\n" + row_text + "\n"

    sqcsa_path.write_text(content, encoding="utf-8")
    print(f"  SQCSA.txt patched for {target}")


def process_folder(folder, dry_run=False):
    folder = folder.rstrip("/")
    folder_path = ROOT / folder
    if not folder_path.exists():
        print(f"[ERROR] folder not found: {folder_path}", file=sys.stderr)
        return

    target = sec_target_name(folder)
    print(f"\n{'=' * 60}")
    print(f"  {target}  ({folder}/)")
    print(f"{'=' * 60}")

    print("  → flawfinder ...", end=" ", flush=True)
    fw = run_flawfinder(folder)
    print(f"hits@4+ = {fw['hits_4plus']}")

    print("  → cppcheck  ...", end=" ", flush=True)
    cpp = run_cppcheck(folder)
    print(f"findings = {cpp['total']}")

    print("  → clang --analyze ...", end=" ", flush=True)
    clang = run_clang_analyze(folder)
    if clang["skipped"]:
        print("skipped")
    else:
        print(f"warnings = {clang['total']}")

    section = build_section(folder, fw, cpp, clang)
    row = summary_row(folder, fw, cpp, clang)

    if dry_run:
        print("\n--- section (dry-run) ---")
        print(section)
        print("--- summary row ---")
        print(row)
        return

    if not SQCSA.exists():
        print(f"[WARN] {SQCSA} not found — writing section to stdout")
        print(section)
        print(row)
        return

    patch_sqcsa(folder, section, row, SQCSA)
    print(f"  Gate: {gate_status(fw, cpp, clang)}")


def main():
    ap = argparse.ArgumentParser(description="Update SQCSA.txt from the static-analysis tools.")
    ap.add_argument("folders", nargs="+", metavar="rel-folder")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    for folder in args.folders:
        process_folder(folder, dry_run=args.dry_run)

    if SQCSA.exists():
        print(f"\nDone.  {SQCSA.relative_to(ROOT)} updated.")


if __name__ == "__main__":
    main()
