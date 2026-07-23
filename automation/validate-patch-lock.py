#!/usr/bin/env python3
"""Validate completeness and local-port freshness of a resolved patch lock."""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


class ValidationError(RuntimeError):
    pass


def load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValidationError(f"unable to read {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ValidationError(f"{path} must contain a JSON object")
    return value


def components(manifest: dict[str, Any], group: str) -> list[dict[str, Any]]:
    value = manifest.get(group, [])
    if not isinstance(value, list) or not all(isinstance(item, dict) for item in value):
        raise ValidationError(f"manifest group {group!r} must be a list of objects")
    return value


def validate_record(name: str, spec: dict[str, Any], record: dict[str, Any]) -> None:
    digest = record.get("sha256")
    if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise ValidationError(f"{name}: invalid resolved SHA-256")
    if not isinstance(record.get("size"), int) or record["size"] <= 0:
        raise ValidationError(f"{name}: invalid resolved size")
    if record.get("target") != spec.get("target"):
        raise ValidationError(f"{name}: lock target differs from the manifest")

    kind = spec.get("kind", "github_tree")
    if kind == "github_tree":
        upstream = record.get("upstream") if record.get("origin") == "local-port" else record
        if not isinstance(upstream, dict):
            raise ValidationError(f"{name}: upstream metadata is missing")
        commit = upstream.get("commit")
        if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit):
            raise ValidationError(f"{name}: upstream commit is not locked")
        if not upstream.get("path") or not upstream.get("url"):
            raise ValidationError(f"{name}: upstream path or URL is missing")

    local_port = spec.get("local_port")
    expected_version = spec.get("local_port_project_version")
    expected_upstream_sha = spec.get("local_port_upstream_sha256")
    if local_port:
        if record.get("origin") != "local-port":
            raise ValidationError(f"{name}: manifest requires a reviewed local port")
        upstream = record.get("upstream")
        if not isinstance(upstream, dict):
            raise ValidationError(f"{name}: local port has no upstream lock")
        if spec.get("project_version_regex") and not expected_version:
            raise ValidationError(
                f"{name}: versioned local port must declare local_port_project_version"
            )
        if expected_version and upstream.get("project_version") != expected_version:
            raise ValidationError(
                f"{name}: reviewed port version {expected_version} is stale; "
                f"selected upstream version is {upstream.get('project_version')!r}"
            )
        if expected_upstream_sha and upstream.get("sha256") != expected_upstream_sha:
            raise ValidationError(
                f"{name}: reviewed port follows upstream SHA-256 "
                f"{expected_upstream_sha}, selected upstream is {upstream.get('sha256')!r}"
            )


def validate(manifest: dict[str, Any], lock: dict[str, Any]) -> None:
    if manifest.get("schema") != 2:
        raise ValidationError("unsupported manifest schema")
    if lock.get("schema") != 3:
        raise ValidationError("unsupported patch-lock schema")

    for group in ("components", "auxiliary_components"):
        specs = components(manifest, group)
        expected = {str(item.get("name", "")) for item in specs}
        if "" in expected or len(expected) != len(specs):
            raise ValidationError(f"manifest group {group!r} has invalid component names")
        records = lock.get(group)
        if not isinstance(records, dict):
            raise ValidationError(f"lock group {group!r} is missing")
        actual = set(records)
        if actual != expected:
            missing = sorted(expected - actual)
            extra = sorted(actual - expected)
            raise ValidationError(
                f"lock group {group!r} differs from manifest: missing={missing}, extra={extra}"
            )
        for spec in specs:
            name = str(spec["name"])
            record = records[name]
            if not isinstance(record, dict):
                raise ValidationError(f"{name}: lock record must be an object")
            validate_record(name, spec, record)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", default="automation/patch-sources.json")
    parser.add_argument("--lock", default="logs/patch-lock.json")
    args = parser.parse_args()
    validate(load(Path(args.manifest)), load(Path(args.lock)))
    print("Patch lock is complete and every reviewed local port is current")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValidationError as exc:
        print(f"patch-lock validation error: {exc}", file=sys.stderr)
        raise SystemExit(2)
