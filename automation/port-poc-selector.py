#!/usr/bin/env python3
"""Adapt the reviewed POC 2.6.1r2 patch to the Valve 6.16 sched.h layout.

The upstream 6.18.3 patch inserts rq::poc_idle_committed using context that is
changed by the BORE port. All other POC hunks apply cleanly. This adapter
removes only that upstream hunk and inserts the identical field at the unique
Valve/BORE anchor before the remaining patch is applied.
"""
from __future__ import annotations

import argparse
import hashlib
import re
from pathlib import Path

EXPECTED_SHA256 = "3e3074017ca672c00ea5418bafb0537b862441664b7174e3c98a4787a0fbaca9"
SECTION_HEADER = "diff --git a/kernel/sched/sched.h b/kernel/sched/sched.h\n"
HUNK_HEADER = "@@ -1135,6 +1135,9 @@ struct rq {\n"
EXPECTED_ADDITIONS = (
    "+#ifdef CONFIG_SCHED_POC_SELECTOR\n"
    "+\tunsigned int\t\tpoc_idle_committed;\n"
    "+#endif\n"
)
FIELD_BLOCK = (
    "#ifdef CONFIG_SCHED_POC_SELECTOR\n"
    "\tunsigned int\t\tpoc_idle_committed;\n"
    "#endif\n"
)
TTWU_RE = re.compile(r"(?m)^(\s*unsigned int\s+ttwu_pending;\s*\n)")


class PortError(RuntimeError):
    pass


def sched_section(text: str) -> str:
    start = text.find(SECTION_HEADER)
    if start < 0:
        raise PortError("POC patch does not contain kernel/sched/sched.h")
    end = text.find("\ndiff --git ", start + len(SECTION_HEADER))
    return text[start : len(text) if end < 0 else end]


def adapt_patch(text: str) -> str:
    section = text.find(SECTION_HEADER)
    if section < 0:
        raise PortError("POC patch does not contain kernel/sched/sched.h")

    section_end = text.find("\ndiff --git ", section + len(SECTION_HEADER))
    if section_end < 0:
        section_end = len(text)

    hunk = text.find(HUNK_HEADER, section, section_end)
    if hunk < 0:
        raise PortError("reviewed rq::poc_idle_committed hunk was not found")

    next_hunk = text.find("\n@@ ", hunk + len(HUNK_HEADER), section_end)
    if next_hunk < 0:
        next_hunk = section_end
    else:
        next_hunk += 1

    body = text[hunk + len(HUNK_HEADER) : next_hunk]
    if EXPECTED_ADDITIONS not in body:
        raise PortError("rq::poc_idle_committed hunk changed upstream")
    if body.count("poc_idle_committed") != 1:
        raise PortError("unexpected rq::poc_idle_committed hunk structure")

    adapted = text[:hunk] + text[next_hunk:]
    adapted_sched = sched_section(adapted)
    if HUNK_HEADER in adapted_sched or EXPECTED_ADDITIONS in adapted_sched:
        raise PortError("rq::poc_idle_committed hunk remains in sched.h")
    return adapted


def adapt_sched_header(text: str) -> str:
    if "poc_idle_committed" in text:
        raise PortError("kernel/sched/sched.h already contains poc_idle_committed")
    matches = list(TTWU_RE.finditer(text))
    if len(matches) != 1:
        raise PortError(f"expected one ttwu_pending anchor, found {len(matches)}")
    match = matches[0]
    return text[: match.end()] + FIELD_BLOCK + text[match.end() :]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("patch", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("sched_header", type=Path)
    args = parser.parse_args()

    patch_bytes = args.patch.read_bytes()
    digest = hashlib.sha256(patch_bytes).hexdigest()
    if digest != EXPECTED_SHA256:
        raise SystemExit(
            "POC upstream bytes changed; review and update the Valve port before building: "
            f"expected {EXPECTED_SHA256}, got {digest}"
        )

    try:
        adapted_patch = adapt_patch(patch_bytes.decode("utf-8"))
        adapted_header = adapt_sched_header(args.sched_header.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, PortError) as exc:
        raise SystemExit(f"POC Valve port failed: {exc}") from exc

    args.output.write_text(adapted_patch, encoding="utf-8")
    args.sched_header.write_text(adapted_header, encoding="utf-8")
    print(
        "Prepared reviewed POC 2.6.1r2 port: inserted rq::poc_idle_committed "
        "at the Valve/BORE ttwu_pending anchor"
    )


if __name__ == "__main__":
    main()
