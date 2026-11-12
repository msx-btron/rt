#!/usr/bin/env python3
"""
rt — Security and quality code audit report.

Runs flawfinder, cppcheck, and clang --analyze on the scalar C runtime and
the host oracle, then prints an ASCII source tree with severity badges.

Assembly backends are not C. They are outside this scan.

Usage:
    python3 scripts/security_report.py [options] [target_folders ...]

Options:
    --color=auto|always|never   Control color output (default: auto)
    --no-color                  Disable all color escapes
    --fast                      Accepted for the btron invocation. No extra skip.
    --all                       Scan the configured modules (the default)
"""

import argparse
import os
import re
import subprocess
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

ANSI = re.compile(r"\033\[[0-9;]*m")

SEC_CFLAGS = [
    "-std=c99",
    "-Wall",
    "-Wextra",
    "-Wformat=2",
    "-fno-strict-aliasing",
    "-fno-builtin",
]

MODULE_CONFIGS = [
    {
        "folder": "src/common/scalar",
        "name": "Scalar C99 runtime",
        "includes": ["-Iinclude"],
        "excludes": [],
        "skip_clang": False,
    },
    {
        "folder": "verify",
        "name": "Host oracle",
        "includes": ["-Iinclude"],
        "excludes": ["verify/build", "verify/.cache"],
        "skip_clang": False,
        "c_files": ["verify/test_host.c", "verify/test_mem.c"],
    },
]


def vlen(text):
    return len(ANSI.sub("", text))


def pad(text, width):
    return text + (" " * max(0, width - vlen(text)))


class Formatter:
    def __init__(self, mode="auto"):
        self.color_enabled = self._eval_color(mode)

    @staticmethod
    def _eval_color(mode):
        if mode == "never" or os.environ.get("NO_COLOR"):
            return False
        if mode == "always":
            return True
        if os.environ.get("CI") or os.environ.get("GITHUB_ACTIONS"):
            return True
        return hasattr(sys.stdout, "isatty") and sys.stdout.isatty()

    def c(self, code, text):
        if not self.color_enabled:
            return text
        return f"\033[{code}m{text}\033[0m"

    def bold(self, text):
        return self.c("1", text)

    def red(self, text):
        return self.c("1;31", text)

    def green(self, text):
        return self.c("1;32", text)

    def yellow(self, text):
        return self.c("1;33", text)

    def cyan(self, text):
        return self.c("1;36", text)

    def blue(self, text):
        return self.c("1;34", text)

    def dim(self, text):
        return self.c("2", text)


def run_cmd(cmd, cwd=ROOT):
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
        return r.stdout, r.stderr, r.returncode
    except FileNotFoundError:
        return "", f"command not found: {cmd[0]}", -1


def tool_exists(tool_name):
    _, _, rc = run_cmd(["which", tool_name])
    return rc == 0


class Finding:
    def __init__(self, tool, file_path, line, severity, category, message):
        self.tool = tool
        self.file_path = file_path
        self.line = line
        self.severity = severity
        self.category = category
        self.message = message


def rel_path(fpath):
    return fpath.replace(str(ROOT) + "/", "")


def c_files_for(cfg):
    if cfg.get("c_files"):
        files = []
        for rel in cfg["c_files"]:
            path = ROOT / rel
            if path.is_file():
                files.append(path)
        return files
    folder = ROOT / cfg["folder"]
    if not folder.exists():
        return []
    if folder.is_file():
        return [folder]
    excludes = cfg.get("excludes", [])
    found = []
    for path in sorted(folder.rglob("*.c")):
        rel = str(path.relative_to(ROOT))
        if any(ex in rel for ex in excludes):
            continue
        if path.name.endswith("test.c") and cfg["folder"] != "verify":
            continue
        found.append(path)
    return found


def collect_flawfinder(cfg):
    if not tool_exists("flawfinder"):
        return []

    cmd = ["flawfinder", "--minlevel=4", "--quiet"]
    for ex in cfg.get("excludes", []):
        cmd.extend(["--exclude", f"*{ex}*"])
    targets = cfg.get("c_files") or [cfg["folder"]]
    for rel in targets:
        cmd.append(str(ROOT / rel))

    stdout, _, _ = run_cmd(cmd)
    findings = []
    pending = None
    hit_re = re.compile(
        r"^(.*?):(\d+):\s*\[(\d+)\]\s*\((.*?)\)\s*(.*?):\s*(.*)$"
    )

    for raw in stdout.splitlines():
        line = raw.rstrip()
        m = hit_re.match(line.strip())
        if m:
            if pending is not None:
                findings.append(pending)
            fpath, line_no, lvl, cat, name, msg = m.groups()
            lvl_int = int(lvl)
            sev = "CRITICAL" if lvl_int >= 5 else "WARNING"
            pending = Finding(
                tool="flawfinder",
                file_path=rel_path(fpath),
                line=int(line_no),
                severity=sev,
                category=f"[{cat}] {name}",
                message=msg.strip(),
            )
        elif pending is not None and line.startswith((" ", "\t")) and line.strip():
            extra = line.strip()
            if pending.message:
                pending.message += " " + extra
            else:
                pending.message = extra
    if pending is not None:
        findings.append(pending)
    return findings


def collect_cppcheck(cfg):
    if not tool_exists("cppcheck"):
        return []

    cmd = [
        "cppcheck",
        "-j4",
        "--std=c99",
        "--enable=warning,portability",
        "--quiet",
    ]
    cmd.extend(cfg.get("includes", []))
    for ex in cfg.get("excludes", []):
        cmd.extend(["-i", str(ROOT / ex)])
    targets = cfg.get("c_files") or [cfg["folder"]]
    for rel in targets:
        cmd.append(str(ROOT / rel))

    stdout, stderr, _ = run_cmd(cmd)
    findings = []
    diag = re.compile(
        r"^(.*?):(\d+):(?:\d+:)?\s*(error|warning|portability|style):\s*(.*?)(?:\s*\[(.*?)\])?$"
    )

    for raw in (stdout + "\n" + stderr).splitlines():
        line = raw.strip()
        if not line or "unhandledChar" in line:
            continue
        m = diag.match(line)
        if not m:
            continue
        fpath, line_no, sev_str, msg, rule = m.groups()
        if sev_str == "error":
            sev = "CRITICAL"
        elif sev_str == "warning":
            sev = "WARNING"
        else:
            sev = "PORTABILITY"
        findings.append(Finding(
            tool="cppcheck",
            file_path=rel_path(fpath),
            line=int(line_no),
            severity=sev,
            category=rule or sev_str,
            message=msg.strip(),
        ))
    return findings


def collect_clang(cfg):
    if cfg.get("skip_clang") or not tool_exists("clang"):
        return []

    files = c_files_for(cfg)
    if not files:
        return []

    cmd = ["clang", "--analyze"]
    cmd.extend(SEC_CFLAGS)
    cmd.extend(cfg.get("includes", []))
    cmd.extend(["-Xanalyzer", "-analyzer-output=text"])
    cmd.extend(str(f) for f in files)

    stdout, stderr, _ = run_cmd(cmd)
    findings = []
    diag = re.compile(r"^(.*?):(\d+):(?:\d+:)?\s*(warning|error):\s*(.*)$")

    for raw in (stdout + "\n" + stderr).splitlines():
        line = raw.strip()
        if "warning:" not in line and "error:" not in line:
            continue
        m = diag.match(line)
        if not m:
            continue
        fpath, line_no, sev_str, msg = m.groups()
        findings.append(Finding(
            tool="clang",
            file_path=rel_path(fpath),
            line=int(line_no),
            severity="CRITICAL" if sev_str == "error" else "WARNING",
            category="clang-analyzer",
            message=msg.strip(),
        ))
    return findings


def build_tree_structure(all_files, findings_by_file):
    tree = {}
    for f in all_files:
        parts = Path(f).parts
        curr = tree
        for p in parts[:-1]:
            curr = curr.setdefault(p, {})
        curr[parts[-1]] = findings_by_file.get(f, [])
    return tree


def format_badge(findings, fmt):
    crits = sum(1 for f in findings if f.severity == "CRITICAL")
    warns = sum(1 for f in findings if f.severity == "WARNING")
    ports = sum(1 for f in findings if f.severity == "PORTABILITY")

    if crits > 0:
        return fmt.red(f"[FAIL: {crits} crit, {warns} warn]")
    if warns > 0:
        return fmt.yellow(f"[WARN: {warns} issues]")
    if ports > 0:
        return fmt.dim(f"[INFO: {ports} port]")
    return fmt.green("[PASS]")


def print_tree(tree, fmt, prefix=""):
    items = sorted(tree.items(), key=lambda x: (isinstance(x[1], list), x[0]))
    total = len(items)

    for idx, (name, val) in enumerate(items):
        is_last = idx == total - 1
        connector = "\\-- " if is_last else "+-- "
        next_prefix = prefix + ("    " if is_last else "|   ")

        if isinstance(val, dict):
            print(f"{prefix}{connector}{fmt.bold(fmt.blue(name + '/'))}")
            print_tree(val, fmt, next_prefix)
            continue

        findings = val
        badge = format_badge(findings, fmt)
        line_lead = f"{prefix}{connector}{fmt.bold(name)} "
        vis = vlen(f"{prefix}{connector}{name} ")
        dots = fmt.dim("." * max(2, 60 - vis))
        print(f"{line_lead}{dots} {badge}")

        if not findings:
            continue
        shown = findings[:8]
        for f in shown:
            tool_tag = f"[{f.tool[:4].upper()}]"
            if f.severity == "CRITICAL":
                tag = fmt.red(f"{tool_tag}:CRIT")
            elif f.severity == "WARNING":
                tag = fmt.yellow(f"{tool_tag}:WARN")
            else:
                tag = fmt.dim(f"{tool_tag}:INFO")
            msg = f.message
            if len(msg) > 55:
                msg = msg[:52] + "..."
            cat = f.category if f.category.startswith("[") else "[" + f.category + "]"
            print(f"{next_prefix}+-- {tag} L{f.line:<4} {fmt.cyan(cat)} {msg}")
        if len(findings) > 8:
            print(f"{next_prefix}\\-- {fmt.dim(f'... and {len(findings) - 8} additional findings')}")


def print_scoreboard(folder_results, fmt):
    width = 78
    sep = "+------------------------------+------------+------------+-----------+------------+"
    hdr = "+==============================+============+============+===========+============+"

    print(fmt.bold(hdr))
    print(fmt.bold("| Module / Folder              | Flawfinder | Cppcheck   | Clang     | Status     |"))
    print(fmt.bold(sep))

    grand_ff = grand_cpp = grand_cl = 0
    any_fail = False
    any_warn = False

    for item in folder_results:
        cfg = item["cfg"]
        findings = item["findings"]
        ff_cnt = sum(1 for f in findings if f.tool == "flawfinder")
        cpp_cnt = sum(1 for f in findings if f.tool == "cppcheck")
        cl_cnt = sum(1 for f in findings if f.tool == "clang")
        crit_cnt = sum(1 for f in findings if f.severity == "CRITICAL")
        grand_ff += ff_cnt
        grand_cpp += cpp_cnt
        grand_cl += cl_cnt

        if crit_cnt > 0:
            status = fmt.red("FAIL")
            any_fail = True
        elif ff_cnt or cpp_cnt or cl_cnt:
            status = fmt.yellow("WARN")
            any_warn = True
        else:
            status = fmt.green("PASS")

        folder_col = fmt.bold(f"{cfg['folder']:<28}")
        cl_txt = "n/a" if cfg.get("skip_clang") else str(cl_cnt)
        print(
            "| "
            + pad(folder_col, 28)
            + " | "
            + pad(str(ff_cnt), 10)
            + " | "
            + pad(str(cpp_cnt), 10)
            + " | "
            + pad(cl_txt, 9)
            + " | "
            + pad(status, 10)
            + " |"
        )

    print(fmt.bold(sep))
    if any_fail:
        overall = fmt.red("FAIL")
    elif any_warn:
        overall = fmt.yellow("WARN")
    else:
        overall = fmt.green("PASS")
    print(
        "| "
        + pad(fmt.bold("TOTAL SOURCE AUDIT"), 28)
        + " | "
        + pad(str(grand_ff), 10)
        + " | "
        + pad(str(grand_cpp), 10)
        + " | "
        + pad(str(grand_cl), 9)
        + " | "
        + pad(overall, 10)
        + " |"
    )
    print(fmt.bold(hdr))
    print()
    return width


def box_line(text, fmt, width):
    print(fmt.bold("|" + pad(text, width) + "|"))


def main():
    parser = argparse.ArgumentParser(description="rt security and quality audit tree")
    parser.add_argument("folders", nargs="*", help="Folder(s) to scan, relative to the repo root")
    parser.add_argument("--color", choices=["auto", "always", "never"], default="auto")
    parser.add_argument("--no-color", action="store_true")
    parser.add_argument("--fast", action="store_true", help="Accepted. This tree has no skipped corpus.")
    parser.add_argument("--all", action="store_true", help="Scan the configured modules")
    args = parser.parse_args()

    fmt = Formatter("never" if args.no_color else args.color)
    width = 78

    print(fmt.bold("+" + "=" * width + "+"))
    box_line("  " + fmt.cyan("rt STATIC ANALYSIS & QUALITY AUDIT REPORT"), fmt, width)
    stamp = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")
    box_line(f"  Timestamp: {stamp}", fmt, width)
    print(fmt.bold("+" + "=" * width + "+"))
    print()

    if args.folders:
        configs = []
        for folder in args.folders:
            folder = folder.rstrip("/")
            matched = [c for c in MODULE_CONFIGS if c["folder"] == folder]
            if matched:
                configs.append(matched[0])
            else:
                configs.append({
                    "folder": folder,
                    "name": folder,
                    "includes": ["-Iinclude"],
                    "excludes": [],
                    "skip_clang": False,
                })
    else:
        configs = MODULE_CONFIGS

    folder_results = []
    findings_by_file = defaultdict(list)
    scanned_files = set()

    print(fmt.bold("[-] Scanning source directories in tree sequence:"))
    for cfg in configs:
        folder = cfg["folder"]
        print(f"    +-- Scanning {fmt.bold(folder + '/')} ...", end="", flush=True)
        if not (ROOT / folder).exists():
            print(f" {fmt.red('missing')}")
            folder_results.append({"cfg": cfg, "findings": []})
            continue

        for path in c_files_for(cfg):
            scanned_files.add(str(path.relative_to(ROOT)))

        combined = (
            collect_flawfinder(cfg)
            + collect_cppcheck(cfg)
            + collect_clang(cfg)
        )
        folder_results.append({"cfg": cfg, "findings": combined})
        for item in combined:
            findings_by_file[item.file_path].append(item)
        print(f" {fmt.green('done')} ({len(combined)} findings)")

    print()
    print(fmt.bold("+" + "-" * width + "+"))
    box_line("  " + fmt.cyan("SOURCE CODE TREE AUDIT"), fmt, width)
    print(fmt.bold("+" + "-" * width + "+"))

    tree = build_tree_structure(scanned_files, findings_by_file)
    print_tree(tree, fmt)
    print()
    print_scoreboard(folder_results, fmt)

    total_crits = sum(
        sum(1 for f in r["findings"] if f.severity == "CRITICAL")
        for r in folder_results
    )
    total_warns = sum(
        sum(1 for f in r["findings"] if f.severity == "WARNING")
        for r in folder_results
    )

    print(fmt.bold("+" + "=" * width + "+"))
    if total_crits:
        verdict = fmt.red("SECURITY & QUALITY GATE: FAILED")
        msg = f"  Detected {total_crits} critical findings."
        note = "  See the tree above for file and line."
    else:
        verdict = fmt.green("SECURITY & QUALITY GATE: PASSED")
        if total_warns:
            msg = f"  {total_warns} warning-level findings. No level-5 hit and no error severity."
        else:
            msg = "  No findings at level 4 or in the analyzer warning set."
        note = "  Catalogued in doc/txt/SQCSA.txt. Assembly backends are outside this scan."
    box_line("  " + verdict, fmt, width)
    box_line(msg, fmt, width)
    box_line(note, fmt, width)
    print(fmt.bold("+" + "=" * width + "+"))
    print()

    missing = [name for name in ("clang", "flawfinder", "cppcheck") if not tool_exists(name)]
    if missing:
        print("missing scanner: " + ", ".join(missing), file=sys.stderr)
        sys.exit(2)
    if total_crits or total_warns:
        sys.exit(1)


if __name__ == "__main__":
    main()
