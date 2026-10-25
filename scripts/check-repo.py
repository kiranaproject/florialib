#!/usr/bin/env python3
"""Repository consistency checks for florialib.

Checks:
  * every library unit is listed in florialib.lpk;
  * every lpk file entry exists;
  * every library unit is present in the florialib.pas umbrella;
  * documentation links resolve and do not use machine-specific file:/// URLs;
  * no build artifacts are tracked in git;
  * the dependency documentation still describes fpGUI as the AggPas provider.
"""

from __future__ import annotations

import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAIN = ROOT / "src" / "main" / "pascal"
LPK = MAIN / "florialib.lpk"
UMBRELLA = MAIN / "florialib.pas"

errors: list[str] = []


def fail(message: str) -> None:
    errors.append(message)


def source_units() -> dict[str, Path]:
    units: dict[str, Path] = {}
    for path in sorted(MAIN.rglob("*.pas")):
        text = path.read_text(encoding="utf-8", errors="replace")
        match = re.search(r"(?im)^\s*unit\s+([A-Za-z0-9_.]+)\s*;", text)
        if match:
            units[match.group(1)] = path
        else:
            fail(f"cannot determine unit name: {path.relative_to(ROOT)}")
    return units


def check_lpk(units: dict[str, Path]) -> None:
    try:
        tree = ET.parse(LPK)
    except ET.ParseError as exc:
        fail(f"cannot parse {LPK.relative_to(ROOT)}: {exc}")
        return

    lpk_units: set[str] = set()
    for item in tree.findall(".//Files/Item"):
        filename_node = item.find("Filename")
        unit_node = item.find("UnitName")
        filename = filename_node.get("Value") if filename_node is not None else None
        unit_name = unit_node.get("Value") if unit_node is not None else None
        if not filename:
            continue
        target = (MAIN / filename).resolve()
        if not target.exists():
            fail(f"lpk references missing file: {filename}")
        if unit_name:
            lpk_units.add(unit_name)

    # The package umbrella unit is the package's main source, not a Files entry.
    expected = {name for name in units if name.lower() != "florialib"}
    for name in sorted(expected - lpk_units):
        fail(f"unit missing from florialib.lpk: {name}")
    for name in sorted(lpk_units - expected):
        fail(f"lpk lists unknown unit: {name}")


def check_umbrella(units: dict[str, Path]) -> None:
    text = UMBRELLA.read_text(encoding="utf-8", errors="replace")
    iface = re.search(r"(?is)\binterface\b(.*?)\b(?:implementation|initialization)\b", text)
    if not iface:
        fail("cannot find interface section in florialib.pas")
        return
    uses = re.search(r"(?is)\buses\b(.*?);", iface.group(1))
    if not uses:
        fail("cannot find uses clause in florialib.pas interface")
        return

    umbrella = set(re.findall(r"\b(Floria(?:\.[A-Za-z0-9_]+)+)\b", uses.group(1)))
    expected = {name for name in units if name.lower() != "florialib"}
    for name in sorted(expected - umbrella):
        fail(f"unit missing from florialib.pas umbrella: {name}")
    for name in sorted(umbrella - expected):
        fail(f"florialib.pas lists unknown unit: {name}")


LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+)\)")


def markdown_files() -> list[Path]:
    files = [ROOT / "README.md", ROOT / "roadmap.md", ROOT / "GEMINI.md"]
    files.extend(sorted((ROOT / "docs").glob("*.md")))
    files.extend(sorted((ROOT / ".agents").rglob("*.md")))
    return [path for path in files if path.exists()]


def check_docs() -> None:
    for path in markdown_files():
        text = path.read_text(encoding="utf-8", errors="replace")
        for target in LINK_RE.findall(text):
            target = target.strip()
            if target.startswith("file:///"):
                fail(f"{path.relative_to(ROOT)}: absolute file link is not portable: {target}")
                continue
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            target = target.split("#", 1)[0].strip("<>")
            if not target:
                continue
            resolved = (path.parent / target).resolve()
            if not resolved.exists():
                fail(
                    f"{path.relative_to(ROOT)}: broken link: {target} "
                    f"(resolved to {resolved.relative_to(ROOT) if resolved.is_relative_to(ROOT) else resolved})"
                )


def check_tracked_artifacts() -> None:
    try:
        tracked = subprocess.check_output(
            ["git", "ls-files"], cwd=ROOT, text=True, stderr=subprocess.PIPE
        ).splitlines()
    except (OSError, subprocess.CalledProcessError) as exc:
        fail(f"cannot run git ls-files: {exc}")
        return

    artifacts = (".o", ".ppu", ".compiled", ".bak", ".lps", ".a", ".so", ".dll")
    for name in tracked:
        if name.endswith(artifacts) or name.startswith("src/main/pascal/lib/"):
            fail(f"build artifact is tracked in git: {name}")


def check_dependency_docs() -> None:
    gemini = (ROOT / "GEMINI.md").read_text(encoding="utf-8", errors="replace")
    roadmap = (ROOT / "roadmap.md").read_text(encoding="utf-8", errors="replace")

    for text, source in ((gemini, "GEMINI.md"), (roadmap, "roadmap.md")):
        lowered = text.lower()
        if "fpgui-framework is not used" in lowered:
            fail(f"{source}: falsely claims fpgui-framework is unused")
        if "decoupled from legacy frameworks" in lowered or "decoupled from fpgui" in lowered:
            fail(f"{source}: falsely claims AggPas is decoupled from fpGUI")
        if "aggpas:2.4.0-snapshot" in lowered:
            fail(f"{source}: still declares the discarded standalone AggPas dependency")

    if "fpgui-framework" not in gemini.lower():
        fail("GEMINI.md must document fpgui-framework as the intended dependency")


def main() -> int:
    units = source_units()
    check_lpk(units)
    check_umbrella(units)
    check_docs()
    check_tracked_artifacts()
    check_dependency_docs()

    if errors:
        print("Repository checks failed:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    print(f"Repository checks passed ({len(units)} library units).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
