#!/usr/bin/env python3
"""Unit tests for private mountpoint safety guard (synthetic directories only)."""
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_system_private_dirs import check_private_mountpoints


def reject(root: Path, reason: str):
    try:
        check_private_mountpoints(root)
    except ValueError as ex:
        assert reason in str(ex), (reason, str(ex))
        return
    raise AssertionError(f"Unsafe fixture accepted: {reason}")


with tempfile.TemporaryDirectory(prefix="alice-system-safe-") as t:
    root = Path(t)
    assert check_private_mountpoints(root) == []
    print("PASS: no sensitive directories")

    for name in ("efs", "userdata", "data", "persist"):
        (root / name).mkdir()
    assert set(check_private_mountpoints(root)) == {"efs", "userdata", "data", "persist"}
    print("PASS: all empty mountpoint placeholders accepted")

    (root / "efs" / "private.bin").write_bytes(b"test fixture - NO REAL DATA")
    reject(root, "/efs contains data")
    (root / "efs" / "private.bin").unlink()
    print("PASS: populated EFS rejected")

    (root / "data" / "hidden").mkdir()
    reject(root, "/data contains data")
    (root / "data" / "hidden").rmdir()
    print("PASS: nested private directories rejected")

    (root / "persist").rmdir()
    (root / "persist").symlink_to(root / "efs", target_is_directory=True)
    reject(root, "/persist is a symlink")
    (root / "persist").unlink()
    print("PASS: symlink private mountpoint rejected")

    (root / "userdata").rmdir()
    (root / "userdata").write_text("data")
    reject(root, "/userdata is not a directory")
    print("PASS: file at private mountpoint rejected")
print("PASS: sensitive-content guard tests")
