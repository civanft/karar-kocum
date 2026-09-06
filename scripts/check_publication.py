#!/usr/bin/env python3
"""Reject secret-bearing filenames and high-confidence credentials before publication.

Complements Gitleaks (including history); never prints matched values.
Default: inspect the working-tree versions of tracked files. --staged: index bytes.
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess  # nosec B404
from pathlib import Path, PurePosixPath

PRIVATE_SUFFIXES = {".pem", ".key", ".p8", ".p12", ".pfx", ".jks", ".keystore", ".mobileprovision"}
PRIVATE_NAMES = {
    "key.properties", "secrets.toml", "credentials.json",
    "application_default_credentials.json", ".netrc", ".npmrc", ".pypirc",
    "id_rsa", "id_ed25519", "id_ecdsa", "ati_admin", "ati_github_deploy",
}
PATTERNS = {
    "private-key": re.compile(rb"-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----"),
    "openai-token": re.compile(rb"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{20,}"),
    "github-token": re.compile(rb"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,})"),
    "aws-access-key": re.compile(rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
    "slack-token": re.compile(rb"\bxox[baprs]-[A-Za-z0-9-]{20,}"),
}


def forbidden_path(path: str) -> bool:
    name = PurePosixPath(path).name.lower()
    # Samples may be tracked, but their CONTENT is scanned like every other file.
    if name.endswith((".example", ".template")):
        return False
    if name == ".env" or name.startswith((".env.", ".secret.")):
        return True
    if name in PRIVATE_NAMES or PurePosixPath(name).suffix in PRIVATE_SUFFIXES:
        return True
    normalized = re.sub(r"[-_]", "", name)
    return name.endswith(".json") and (
        "serviceaccount" in normalized or "firebaseadminsdk" in normalized
        or "credentials" in normalized
    )


def scan_content(data: bytes) -> list[tuple[str, int]]:
    return [
        (name, data[:match.start()].count(b"\n") + 1)
        for name, pattern in PATTERNS.items()
        for match in pattern.finditer(data)
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", action="store_true", help="inspect exact index contents")
    args = parser.parse_args()
    git = shutil.which("git")
    if git is None:
        print("FAIL: git executable was not found.")
        return 2
    # Executable is resolved with shutil.which; arguments are fixed.
    root = Path(subprocess.check_output(  # nosec B603
        [git, "rev-parse", "--show-toplevel"], text=True,
    ).strip())
    entries = subprocess.check_output(  # nosec B603
        [git, "ls-files", "--stage", "-z"], cwd=root,
    ).split(b"\0")
    violations: list[str] = []
    count = 0
    for entry in filter(None, entries):
        metadata, raw_path = entry.split(b"\t", 1)
        mode, object_id, stage = metadata.split()
        path = raw_path.decode("utf-8", errors="surrogateescape")
        count += 1
        if stage != b"0":
            violations.append(f"{path}: unresolved merge")
            continue
        if forbidden_path(path):
            violations.append(f"{path}: secret-bearing filename")
        if mode == b"120000":
            violations.append(f"{path}: symlink needs explicit publication review")
            continue
        if mode == b"160000":
            violations.append(f"{path}: submodule needs a separate security audit")
            continue
        if args.staged:
            # The object id is obtained from Git's own index, not user input.
            data = subprocess.check_output(  # nosec B603
                [git, "cat-file", "blob", object_id], cwd=root,
            )
        else:
            target = root / path
            if not target.exists():
                continue
            if target.is_symlink():
                violations.append(f"{path}: working-tree symlink")
                continue
            data = target.read_bytes()
        for category, line in scan_content(data):
            violations.append(f"{path}:{line}: {category} (value redacted)")
    if violations:
        for violation in violations:
            print(violation)
        print(f"FAIL: {len(violations)} publication issue(s); no values printed.")
        return 1
    print(f"PASS: {count} tracked entries; no forbidden filenames/high-confidence secrets.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
