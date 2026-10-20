#!/usr/bin/env python3
"""Fail closed on private-content directories before publishing SYSTEM V2.

Android SYSTEM partitions sometimes contain EMPTY /efs, /data, or /persist
mountpoint directories. Their presence is not itself proof of private data.
This check accepts only genuine empty directories; it rejects symlinks,
nonempty directories, and regular files. It never prints directory contents.
"""
import argparse
from pathlib import Path

PRIVATE_DIRS = ("efs", "userdata", "data", "persist")


def check_private_mountpoints(system_root: Path) -> list[str]:
    if not system_root.is_dir():
        raise ValueError("Not a mounted Android SYSTEM directory")
    placeholders = []
    for name in PRIVATE_DIRS:
        target = system_root / name
        if target.is_symlink():
            raise ValueError(f"/{name} is a symlink, refusing export")
        if not target.exists():
            continue
        if not target.is_dir():
            raise ValueError(f"/{name} is not a directory, refusing export")
        if any(target.iterdir()):
            raise ValueError(
                f"/{name} contains data, refusing public export. "
                "Inspect privately and do not upload EFS/NV/identity data."
            )
        placeholders.append(name)
    return placeholders


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("system_root", type=Path)
    args = parser.parse_args()
    try:
        empty_dirs = check_private_mountpoints(args.system_root)
    except (OSError, ValueError) as exc:
        parser.exit(1, f"PRIVATE_DATA_GUARD_BLOCKED: {exc}\n")
    print("PRIVATE_DATA_GUARD_PASS")
    for name in empty_dirs:
        print(f"EMPTY_PLACEHOLDER_ALLOWED=/{name}")
    print("No private EFS, NV, IMEI or user data were read or displayed.")


if __name__ == "__main__":
    main()
