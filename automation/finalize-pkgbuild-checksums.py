#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import subprocess
from pathlib import Path


class ChecksumError(RuntimeError):
    pass


def array_bounds(text: str, variable: str) -> tuple[int, int]:
    start = re.search(rf"(?m)^{re.escape(variable)}=\(", text)
    if not start:
        raise ChecksumError(f"{variable} array not found")

    index = start.end()
    quote: str | None = None
    escaped = False
    depth = 1
    while index < len(text):
        character = text[index]
        if escaped:
            escaped = False
        elif character == "\\":
            escaped = True
        elif quote:
            if character == quote:
                quote = None
        elif character in ("'", '"'):
            quote = character
        elif character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
            if depth == 0:
                return start.start(), index + 1
        index += 1

    raise ChecksumError(f"unterminated {variable} array")


def evaluated_array(path: Path, variable: str) -> list[str]:
    command = (
        'set -Eeuo pipefail; source "$1"; '
        f'declare -p {variable} >/dev/null; '
        f'printf "%s\\0" "${{{variable}[@]}}"'
    )
    try:
        result = subprocess.run(
            ["bash", "-c", command, "bash", str(path)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.decode("utf-8", errors="replace").strip()
        raise ChecksumError(f"unable to evaluate {variable} array: {stderr}") from exc

    return [entry.decode("utf-8") for entry in result.stdout.split(b"\0") if entry]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pkgbuild", default="PKGBUILD")
    parser.add_argument("--generated", required=True)
    parser.add_argument("--report", default="logs/checksum-validation.txt")
    args = parser.parse_args()

    pkgbuild_path = Path(args.pkgbuild)
    generated_path = Path(args.generated)
    text = pkgbuild_path.read_text(encoding="utf-8")

    sources = evaluated_array(pkgbuild_path, "source")
    checksums = evaluated_array(generated_path, "sha256sums")
    if len(sources) != len(checksums):
        raise ChecksumError(
            f"source/checksum count mismatch: {len(sources)} sources, {len(checksums)} checksums"
        )

    vcs_indexes = {
        index
        for index, source in enumerate(sources)
        if "git+" in source or source.startswith(("git://", "svn+", "hg+", "bzr+"))
    }
    invalid: list[str] = []
    skip_indexes: list[int] = []
    for index, checksum in enumerate(checksums):
        if checksum == "SKIP":
            skip_indexes.append(index)
            if index not in vcs_indexes:
                invalid.append(f"non-VCS source uses SKIP: {sources[index]}")
        elif not re.fullmatch(r"[0-9a-f]{64}", checksum):
            invalid.append(f"invalid SHA-256 for {sources[index]}: {checksum}")

    if invalid:
        raise ChecksumError("; ".join(invalid))

    replacement = "sha256sums=(\n" + "\n".join(
        f"  '{checksum}'" for checksum in checksums
    ) + "\n)"
    sha_start, sha_end = array_bounds(text, "sha256sums")
    pkgbuild_path.write_text(
        text[:sha_start] + replacement + text[sha_end:], encoding="utf-8"
    )

    report = Path(args.report)
    report.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        f"sources={len(sources)}",
        f"sha256={len(checksums) - len(skip_indexes)}",
        f"vcs_skip={len(skip_indexes)}",
    ]
    lines.extend(f"vcs_skip_source={sources[index]}" for index in skip_indexes)
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ChecksumError as exc:
        print(f"checksum error: {exc}")
        raise SystemExit(2)
