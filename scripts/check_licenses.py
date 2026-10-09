#!/usr/bin/env python3
"""Check that every locked Terraform provider appears in LICENSE-3rdparty.csv."""

import csv
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]
LOCK_FILES = (ROOT / ".terraform.lock.hcl", ROOT / "examples/basic/.terraform.lock.hcl")
CSV_FILE = ROOT / "LICENSE-3rdparty.csv"
FIELDS = ("Component", "Origin", "License", "Copyright")
LOCK_BLOCK = re.compile(r'^provider "([^"]+)" \{\n(.*?)^\}', re.MULTILINE | re.DOTALL)
LOCK_VERSION = re.compile(r'^[ \t]*version[ \t]*=[ \t]*"([^"]+)"[ \t]*$', re.MULTILINE)
CSV_PROVIDER = re.compile(r"^([^/\s]+/[^/\s]+) Terraform provider (\S+)$")


def locked_providers(path):
    content = path.read_text()
    blocks = LOCK_BLOCK.findall(content)
    if len(blocks) != len(re.findall(r'^provider "', content, re.MULTILINE)):
        raise ValueError(f"Could not parse every provider block in {path.relative_to(ROOT)}")

    providers = set()
    for source, body in blocks:
        if not source.startswith("registry.terraform.io/"):
            raise ValueError(f"Unsupported provider source {source} in {path.relative_to(ROOT)}")
        versions = LOCK_VERSION.findall(body)
        if len(versions) != 1:
            raise ValueError(f"Expected one version for {source} in {path.relative_to(ROOT)}")
        providers.add((source.removeprefix("registry.terraform.io/").lower(), versions[0]))
    return providers


def listed_providers(path):
    providers = set()
    with path.open(newline="") as stream:
        reader = csv.DictReader(stream)
        if tuple(reader.fieldnames or ()) != FIELDS:
            raise ValueError(f"{path.name} must have the columns {', '.join(FIELDS)}")
        for line_number, row in enumerate(reader, start=2):
            if None in row or any(not value or not value.strip() for value in row.values()):
                raise ValueError(f"Incomplete CSV row at {path.name}:{line_number}")
            origin = urlsplit(row["Origin"])
            if origin.scheme != "https" or not origin.netloc:
                raise ValueError(f"Origin must be an HTTPS URL at {path.name}:{line_number}")
            match = CSV_PROVIDER.fullmatch(row["Component"])
            if match:
                provider = (match[1].lower(), match[2])
                if provider in providers:
                    raise ValueError(f"Duplicate provider {match[1]} {match[2]} in {path.name}")
                providers.add(provider)
    return providers


def main():
    try:
        locked = set().union(*(locked_providers(path) for path in LOCK_FILES))
        listed = listed_providers(CSV_FILE)
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1

    missing = locked - listed
    stale = listed - locked
    for provider, version in sorted(missing):
        print(f"Missing from {CSV_FILE.name}: {provider} {version}", file=sys.stderr)
    for provider, version in sorted(stale):
        print(f"Not present in a lock file: {provider} {version}", file=sys.stderr)
    if missing or stale:
        return 1

    print(f"{CSV_FILE.name} covers {len(locked)} locked provider releases")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
