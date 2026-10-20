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
echo "STAGED_FILES_BEFORE=$(git diff --cached --name-only | wc -l)"
git lfs version >/dev/null
IMPORT_STATE="staged"
if git diff --cached --quiet; then
  # Previous run may already have committed the 4,876 files, OR its index
  # may have been cleared. These two states need different recovery paths.
  if git cat-file -e HEAD:metadata/system-v2-image.sha256 2>/dev/null; then
    committed_sha="$(git show HEAD:metadata/system-v2-image.sha256 | tr -d '[:space:]')"
    [[ "$committed_sha" = "$EXPECTED_IMAGE_SHA256" ]] ||
      die "HEAD contains a DIFFERENT SYSTEM image; refusing to push"
    committed_files="$(git ls-tree -r --name-only HEAD -- system | wc -l)"
    [[ "$committed_files" -ge 4500 ]] ||
      die "HEAD contains only $committed_files SYSTEM files; incomplete import"
    [[ -z "$(git status --porcelain --untracked-files=all -- system metadata .gitattributes)" ]] ||
      die "Already committed SYSTEM has local changes; review before pushing"
    IMPORT_STATE="already-committed"
    echo "Detected complete existing SYSTEM V2 commit with $committed_files files; push only"
  else
    echo "Index is empty, but extracted files exist. Restaging without re-extraction..."
    git add .gitattributes system metadata
    git diff --cached --quiet &&
      die "No staged SYSTEM files after git add; check local files before continuing"
    echo "STAGED_FILES_AFTER_RESTAGE=$(git diff --cached --name-only | wc -l)"
  fi
fi
if [[ "$IMPORT_STATE" = staged ]]; then
  # Prebuilt OEM files legitimately contain trailing whitespace; check only
  # the newly generated metadata instead of changing raw ROM bytes.
  git diff --cached --check -- metadata .gitattributes
fi

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

remote_head="$(git ls-remote --heads origin "refs/heads/$BRANCH")" ||
  die "Cannot check remote branch (network or GitHub authentication)"
[[ -z "$remote_head" ]] ||
  die "Remote baseline already exists. Refusing overwrite."
if [[ "$IMPORT_STATE" = staged ]]; then
  git commit -m "baseline: extracted Android16 Camera+Video6 SYSTEM V2 EROFS"
else
  echo "Using existing local baseline commit $(git rev-parse --short HEAD)"
fi
echo "Pushing LFS objects and baseline branch..."
git push -u origin "$BRANCH"
echo "PUBLISHED: https://github.com/HaloT455/SystemDreamlte/tree/$BRANCH"
