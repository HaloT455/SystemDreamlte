#!/usr/bin/env bash
# ALICE Camera+Video6 SYSTEM V2: export an EROFS filesystem tree to Git/LFS.
# Runs only on owner's Zorin laptop; NEVER writes to the input image or SYSTEM V1.
set -Eeuo pipefail
IMAGE="${1:-/mnt/alice-ssd/ALICE_SYSTEM/OUTPUT/system_alice_camera_v2.img}"
MODE="${2:-inspect}"
BASE="/mnt/alice-ssd/ALICE_SYSTEM"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="${ALICE_IMPORT_WORK:-$BASE/GITHUB_SYSTEM_V2_IMPORT}"
REPO="$WORK/SystemDreamlte"
MNT="$WORK/mount-ro"
REMOTE="https://github.com/HaloT455/SystemDreamlte.git"
BRANCH="baseline/system-v2-camera"

die() { echo "ERROR: $*" >&2; exit 1; }
[[ "$MODE" == inspect || "$MODE" == publish ]] ||
  die "Usage: bash $0 [path-to-SYSTEM-V2.img] [inspect|publish]"
[[ -f "$IMAGE" ]] || {
  echo "SYSTEM V2 file not found: $IMAGE" >&2
  echo "Check candidates, NOT SYSTEM V1:" >&2
  find "$BASE" -maxdepth 5 -type f \( -iname '*system*v2*.img' -o -iname '*system*camera*.img' \) -print 2>/dev/null | head -40 >&2 || :
  exit 2
}
IMAGE="$(realpath "$IMAGE")"
[[ "$IMAGE" != "$BASE/BASE/system_original.img" ]] ||
  die "SYSTEM V1 selected; not a camera-working V2 image"
[[ "$IMAGE" != "$REPO/"* ]] || die "Input image must be outside the export checkout"
command -v file >/dev/null || die "sudo apt install file"
echo "SOURCE_IMAGE=$IMAGE"
echo "IMAGE_BYTES=$(stat -c %s "$IMAGE")"
echo "IMAGE_TYPE=$(file -b "$IMAGE")"
echo "SHA256=$(sha256sum "$IMAGE" | cut -d' ' -f1)"
echo "MODE=$MODE; REMOTE=$REMOTE; BRANCH=$BRANCH"
echo "NOTICE: Extracted SYSTEM binaries are NOT original AOSP/Samsung source code."
echo "NOTICE: GitHub repo is PUBLIC; publishing proprietary code requires authorization."
if [[ "$MODE" == inspect ]]; then
  echo "INSPECT_COMPLETE. No mount, extraction, or upload occurred."
  exit 0
fi

[[ "${ALICE_CONFIRM_PUBLIC_PUBLISH:-}" == YES ]] ||
  die "Review license/redistribution rights first. Then run with ALICE_CONFIRM_PUBLIC_PUBLISH=YES"
for cmd in git rsync python3 sudo mount umount mountpoint sha256sum; do
  command -v "$cmd" >/dev/null || die "Missing $cmd (install git git-lfs rsync)"
done
git lfs version >/dev/null 2>&1 || die "Install git-lfs: sudo apt install git-lfs"
[[ -d "$BASE" ]] || die "SSD ALICE_SYSTEM not mounted"
mkdir -p "$WORK" "$MNT"
[[ ! -e "$REPO/.git" && ! -e "$REPO/system" ]] ||
  die "Checkout exists at $REPO. To retry a failed push: cd '$REPO' && git push -u origin '$BRANCH'"
[[ ! -d "$REPO" || -z "$(ls -A "$REPO")" ]] || die "$REPO is not empty"
mountpoint -q "$MNT" && die "Mountpoint already active"
free_bytes="$(df -B1 --output=avail "$WORK" | tail -1 | tr -d '[:space:]')"
needed_bytes="$(( $(stat -c %s "$IMAGE") * 2 + 1073741824 ))"
[[ "$free_bytes" -ge "$needed_bytes" ]] ||
  die "Insufficient SSD space: available $free_bytes, conservative minimum $needed_bytes"
if git ls-remote --exit-code --heads "$REMOTE" "refs/heads/$BRANCH" >/dev/null 2>&1; then
  die "Baseline already exists on GitHub; will not overwrite it"
fi

mounted=0
cleanup() {
  if [[ "$mounted" == 1 ]]; then sudo umount "$MNT" || echo "Manually unmount: $MNT" >&2; fi
}
trap cleanup EXIT
echo "Mounting source SYSTEM V2 read-only..."
sudo mount -t erofs -o ro,loop,nosuid,nodev "$IMAGE" "$MNT" ||
  die "Could not mount as EROFS. Check IMAGE_TYPE; DO NOT convert in place"
mounted=1
[[ -f "$MNT/build.prop" || -f "$MNT/system/build.prop" ||
   -d "$MNT/etc" || -d "$MNT/system/etc" ]] ||
  die "Mounted file does not look like Android SYSTEM"
sudo python3 "$SCRIPT_DIR/check_system_private_dirs.py" "$MNT" || die "Private-data check failed"

git clone --quiet "$REMOTE" "$REPO"
cd "$REPO"
git switch -c "$BRANCH"
git lfs install --local
mkdir -p system metadata
sudo python3 - "$MNT" "$REPO/metadata/system-v2-fs.json" <<'PY'
import base64, json, os, stat, sys
from pathlib import Path
root = Path(sys.argv[1]); out = Path(sys.argv[2])
items = []
for parent, dirs, files in os.walk(root, followlinks=False):
    for name in sorted(dirs+files):
        p = Path(parent)/name; s = p.lstat()
        if stat.S_ISCHR(s.st_mode) or stat.S_ISBLK(s.st_mode):
            raise RuntimeError("Unexpected device node")
        kind = ("link" if stat.S_ISLNK(s.st_mode) else
                "dir" if stat.S_ISDIR(s.st_mode) else
                "file" if stat.S_ISREG(s.st_mode) else "other")
        rec = dict(path=p.relative_to(root).as_posix(), type=kind,
                   mode=stat.S_IMODE(s.st_mode), uid=s.st_uid, gid=s.st_gid,
                   size=s.st_size, inode=s.st_ino, nlink=s.st_nlink,
                   mtime_ns=s.st_mtime_ns)
        if kind == "link": rec["target"] = os.readlink(p)
        try:
            rec["selinux_b64"] = base64.b64encode(
                os.getxattr(p,"security.selinux",follow_symlinks=False)
            ).decode("ascii")
        except (OSError, ValueError): pass
        items.append(rec)
out.write_text(json.dumps(dict(
    format="ALICE_SYSTEM_V2_EROFS_INVENTORY", entries=items,
    warning="Git does not retain uid/gid/SELinux/hardlink relationships",
), ensure_ascii=False, indent=2)+"\n")
print("EROFS manifest entries:", len(items))
PY
sudo chown "$(id -u):$(id -g)" "$REPO/metadata/system-v2-fs.json"
sudo rsync -aH --chown="$(id -u):$(id -g)" "$MNT/" "$REPO/system/"
chmod -R u+rwX "$REPO/system"
sudo umount "$MNT"
mounted=0

sha256sum "$IMAGE" | cut -d' ' -f1 > metadata/system-v2-image.sha256
{
  echo "IMAGE_NAME=$(basename "$IMAGE")"
  echo "IMAGE_BYTES=$(stat -c %s "$IMAGE")"
  echo "EXPORTED_AT_UTC=$(date -u +%FT%TZ)"
  echo "SOURCE_DIRECTORY=system/"
  echo "SOURCE_IS_EROFS=1"
} > metadata/system-v2-export.properties

git lfs track '*.apk' '*.apex' '*.capex' '*.jar' '*.dex' '*.odex' '*.vdex' '*.oat' '*.art'
git lfs track '*.so' '*.bin' '*.dat' '*.img' '*.zip' '*.xz' '*.ogg' '*.mp3' '*.mp4' '*.webm'
git lfs track '*.ttf' '*.otf' '*.wav' '*.pak' '*.blob' '*.db' '*.sqlite'
while IFS= read -r -d '' big; do
  rel="${big#"$REPO/"}"
  git lfs track -- "$rel"
done < <(find "$REPO/system" -type f -size +49M -print0)
echo "TREE_SIZE=$(du -sh "$REPO/system" | cut -f1)"
echo "LFS quotas and GitHub account permissions may block large pushes."

git add .gitattributes system metadata
git diff --cached --check
echo "STAGED_FILES=$(git diff --cached --name-only | wc -l)"
git commit -m "baseline: extracted Android16 Camera+Video6 SYSTEM V2 EROFS"
git push --set-upstream origin "$BRANCH"
echo "PUBLISHED: https://github.com/HaloT455/SystemDreamlte/tree/$BRANCH"
echo "Keep the original SYSTEM V2 image on the SSD for recovery."
