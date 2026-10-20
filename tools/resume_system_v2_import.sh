#!/usr/bin/env bash
# Resume an EXTRACTED+STAGED Camera-working SYSTEM V2 import.
# Does not mount the image, re-extract files, or force-push.
set -Eeuo pipefail
CHECKOUT="${1:-/mnt/alice-ssd/ALICE_SYSTEM/GITHUB_SYSTEM_V2_IMPORT/SystemDreamlte}"
BRANCH="baseline/system-v2-camera"
EXPECTED_IMAGE_SHA256="2a28920a8c9788e9c90fce78723f77ef60fa34e79906ff9846b7985dbec8c593"
die() { echo "ERROR: $*" >&2; exit 1; }
[[ -d "$CHECKOUT/.git" ]] || die "Staged checkout missing: $CHECKOUT"
cd "$CHECKOUT"
[[ "$(git branch --show-current)" = "$BRANCH" ]] || die "Wrong branch. Expected $BRANCH"
[[ "$(git remote get-url origin)" = "https://github.com/HaloT455/SystemDreamlte.git" ]] ||
  die "Unexpected origin; stop before publishing."
[[ -f metadata/system-v2-image.sha256 ]] || die "Missing imported SYSTEM V2 hash"
[[ "$(tr -d '[:space:]' < metadata/system-v2-image.sha256)" = "$EXPECTED_IMAGE_SHA256" ]] ||
  die "Staged image identity mismatch! Refusing upload."
[[ -f metadata/system-v2-fs.json && -d system/system ]] || die "Missing extracted SYSTEM V2 tree"
[[ -f .gitattributes ]] || die "LFS attributes missing"
[[ "${ALICE_CONFIRM_PUBLIC_PUBLISH:-}" == YES ]] ||
  die "Repo is public. Confirm redistribution rights with ALICE_CONFIRM_PUBLIC_PUBLISH=YES"

echo "CHECKOUT=$CHECKOUT"
echo "BASELINE_IMAGE_SHA256=$EXPECTED_IMAGE_SHA256"
echo "STAGED_FILES=$(git diff --cached --name-only | wc -l)"
git lfs version >/dev/null
git diff --cached --quiet && die "Nothing staged; do not create an empty baseline"
git diff --cached --check -- metadata .gitattributes

python3 - <<'PY'
import json, subprocess
from pathlib import Path
data = json.loads(Path("metadata/system-v2-fs.json").read_text())
count = len(data["entries"])
assert count == 5380, f"Expected 5,380 SYSTEM V2 entries, found {count}"
for item in data["entries"]:
    path = item["path"].lstrip("/")
    assert not any(path.startswith(s) for s in
                   ("efs/", "data/", "userdata/", "persist/")), \
        "Private directory includes subpaths. Stop and review offline."
print("PASS: original SYSTEM inventory: 5,380 entries; no private directory content")

# GitHub rejects individual regular Git blobs >100 MB. LFS pointers are small.
stage = subprocess.check_output(["git", "ls-files", "--stage", "-z"]).split(b"\0")
oids = []
for rec in stage:
    if not rec:
        continue
    header, _, rel = rec.partition(b"\t")
    mode, oid, _ = header.split()
    if mode in (b"100644", b"100755"):
        oids.append((oid.decode(), rel.decode("utf-8", "surrogateescape")))
dedup = sorted({oid for oid, _ in oids})
assert dedup, "No tracked files"
r = subprocess.run(["git", "cat-file", "--batch-check=%(objectname) %(objectsize)"],
                   input="\n".join(dedup) + "\n", text=True,
                   capture_output=True, check=True)
sizes = {}
for line in r.stdout.splitlines():
    oid, size = line.split()
    sizes[oid] = int(size)
over = [f"{rel}: {sizes[oid]} bytes" for oid, rel in oids
        if sizes[oid] > 95 * 1024 * 1024]
if over:
    raise SystemExit("Large non-LFS Git blobs require review:\n" + "\n".join(over[:15]))
print("PASS: no non-LFS staged Git blobs exceed 95 MiB")
PY

if git ls-remote --exit-code --heads origin "refs/heads/$BRANCH" >/dev/null 2>&1; then
  die "Remote baseline already exists. Refusing overwrite."
fi
git commit -m "baseline: extracted Android16 Camera+Video6 SYSTEM V2 EROFS"
echo "Committed locally. Pushing staged LFS objects and baseline branch..."
git push -u origin "$BRANCH"
echo "PUBLISHED: https://github.com/HaloT455/SystemDreamlte/tree/$BRANCH"
