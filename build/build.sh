#!/usr/bin/env bash
# =============================================================================
# Build Debian firmware for UFI devices (OpenStick msm8916 family) -- kernel
# + boot.img only.
#
# Flow:
#   optional apt mirror switch -> install toolchain -> copy source
#   (/source, read-only mount) to /build/src -> (optional) apply RNDIS MS IAD
#   patch -> kernel config (default kernel-rebuild.config) -> cross compile
#   -> make-kpkg produces debs -> download OpenStick base pack debian.zip
#   -> simg2img + qemu chroot installs the new kernel and generates a matching
#   initrd -> cat Image.gz + dtb -> mkbootimg -> <device>-boot.img
#   -> copy artifacts into /dist
#
# Notes:
#   * The toolchain is installed here (not in the Dockerfile) so that
#     APT_SOURCE also applies to it; on a persistent container the install
#     step is skipped once the tools are present.
#   * This script does the "kernel + boot.img" scope only; the rootfs.img is
#     NOT repacked. The base pack is only used in chroot to install the new
#     kernel so that a matching initrd is generated.
#   * Chroot needs mount + qemu-user-static inside the container:
#     compose.yml.example therefore sets privileged: true.
#   * Runs as root inside the container (no sudo, tutorial's sudo prefixes
#     are dropped).
#   * Env vars: DEVICE / ENABLE_RNDIS_MS_IAD / USE_REBUILD_CONFIG /
#     EXTRA_CONFIG / APT_SOURCE / APT_SECURITY_SOURCE / ENABLE_APT_SRC /
#     BASE_URL / CMDLINE (defaults in Dockerfile)
#
# Usage (inside the container):
#   build.sh            # full build
#   build.sh bash       # drop into an interactive shell only
# =============================================================================
set -euo pipefail

log() { printf '\n\033[1;32m[build]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[build] error\033[0m %s\n' "$*" >&2; exit 1; }

# Rewrite /etc/apt/sources.list to use the given mirror, then run a single
# apt-get update. Accepts a bare host or a full URL (mirrors.nju.edu.cn or
# http://mirrors.aliyun.com/ubuntu). The security suites default to the SAME
# mirror (merged layout: Aliyun/Tencent/...); mirrors that serve
# focal-security from a separate /ubuntu-security (USTC/TUNA/...) must set
# APT_SECURITY_SOURCE explicitly. No probing or fallbacks: a wrong config
# fails loudly and is the user's to fix (unset APT_SOURCE for official).
# ENABLE_APT_SRC=true writes active deb-src lines, else commented ones.
switch_apt_mirror() {
  local url="${1:-}" sec="${2:-}" main="" src_pref="deb-src" src_state="enabled"
  [ "$ENABLE_APT_SRC" = "true" ] || { src_pref="# deb-src"; src_state="disabled (commented)"; }
  case "$url" in
    http://* | https://*) main="${url%/}" ;;
    *) main="http://${url%/}" ;;
  esac
  # bare host without a path -> append the standard /ubuntu
  case "$main" in
    *://*/*) : ;;
    *) main="$main/ubuntu" ;;
  esac
  [ -n "$sec" ] || sec="$main"
  log "apt mirror: $main (security: $sec) | deb-src: $src_state"
  cat > /etc/apt/sources.list <<EOF
deb $main focal main restricted universe multiverse
$src_pref $main focal main restricted universe multiverse
deb $main focal-updates main restricted universe multiverse
$src_pref $main focal-updates main restricted universe multiverse
deb $main focal-backports main restricted universe multiverse
$src_pref $main focal-backports main restricted universe multiverse
deb $sec focal-security main restricted universe multiverse
$src_pref $sec focal-security main restricted universe multiverse
EOF
  # refresh the indexes for the new source URIs; cached lists are keyed per
  # source URI, so without this apt cannot locate any package
  apt-get update
}

# --- argument dispatch --------------------------------------------------------
case "${1:-}" in
  build | "") : ;;
  bash | shell | interactive) exec bash -l ;;
  # keep the container alive without starting a build; run builds later with
  # `docker exec <name> /build.sh build` (see build/README.md)
  wait | daemon) exec sleep infinity ;;
  *) die "unknown argument: $1 (use: build / bash / wait)" ;;
esac

SUPPORTED_DEVICES="ufi001b ufi001c sp970 uz801"
case " $SUPPORTED_DEVICES " in
  *" $DEVICE "*) : ;;
  *) die "unsupported device: $DEVICE (choose from: $SUPPORTED_DEVICES, or add one matching the dts filenames)" ;;
esac

SRC=/source                 # repository root (read-only mount)
BUILD=/build                # container working dir
SRC_COPY="$BUILD/src"       # kernel source copy in a named volume: the build
                            # tree survives between runs and make rebuilds
                            # only what changed (FULL_REBUILD=true to wipe)
CACHE="$BUILD/cache"        # base-pack cache (named volume, reused across runs)
STAGE="$BUILD/stage"        # staging dir for assembling the boot image
OUT=/dist                   # artifact output dir (mounted to host build/dist)

log "target device: $DEVICE | RNDIS MS IAD patch: $ENABLE_RNDIS_MS_IAD | full .config: $USE_REBUILD_CONFIG"
nproc

# --- 1. optional apt mirror switch + toolchain install --------------------------
# no wget pre-step: when APT_SOURCE is set, the very first apt-get update
# already runs against the mirror
updated=0
if [ -n "${APT_SOURCE:-}" ]; then
  log "switching apt source to $APT_SOURCE"
  if switch_apt_mirror "$APT_SOURCE" "${APT_SECURITY_SOURCE:-}"; then
    updated=1   # switch_apt_mirror already ran apt-get update
  else
    die "apt mirror update failed - fix APT_SOURCE / APT_SECURITY_SOURCE, or unset APT_SOURCE to use the official sources"
  fi
fi

# the toolchain deps live here (not in the Dockerfile) so APT_SOURCE applies
# to them; skipped on a persistent container where they are already present
if command -v make-kpkg >/dev/null && command -v aarch64-linux-gnu-gcc >/dev/null \
   && command -v mkbootimg >/dev/null && command -v qemu-aarch64-static >/dev/null \
   && command -v rsync >/dev/null && command -v cpio >/dev/null \
   && command -v debugfs >/dev/null; then
  log "toolchain already installed, skipping apt"
else
  [ "${updated:-}" = "1" ] || apt-get update
  log "installing toolchain"
  apt-get install -y --no-install-recommends \
    binfmt-support qemu-user-static \
    gcc-aarch64-linux-gnu kernel-package fakeroot \
    android-sdk-libsparse-utils mkbootimg \
    bison flex bc pkg-config libncurses-dev libssl-dev \
    git unzip wget rsync cpio e2fsprogs ca-certificates
fi
log "image: $(. /etc/os-release; echo "$PRETTY_NAME") | host arch: $(uname -m) | gcc: $(aarch64-linux-gnu-gcc --version | head -1)"
free -h | head -2

# --- 2. prepare: sync the kernel source -----------------------------------------
# overlay-sync /source onto the preserved build tree (tar keeps file mtimes,
# so make only recompiles what actually changed); FULL_REBUILD=true wipes it
rm -rf "$STAGE"
if [ "${FULL_REBUILD:-false}" = "true" ]; then
  log "FULL_REBUILD=true, wiping $SRC_COPY"
  rm -rf "$SRC_COPY"
fi
mkdir -p "$SRC_COPY" "$STAGE" "$CACHE" "$OUT"
log "syncing kernel source (/source -> $SRC_COPY, excluding .git/build/workspace)"
tar -C "$SRC" --exclude=.git --exclude=build --exclude=workspace -cf - . \
  | tar -C "$SRC_COPY" -xf -
[ -f "$SRC_COPY/Makefile" ] || die "source copy incomplete, check that $SRC is the repo root"
[ -f "$SRC_COPY/patch/rndis-ms-iad_desc.patch" ] || die "patch/rndis-ms-iad_desc.patch missing"

# --- 3. optional RNDIS MS IAD patch (idempotent across runs) --------------------
cd "$SRC_COPY"
if patch -p1 --dry-run -R < patch/rndis-ms-iad_desc.patch >/dev/null 2>&1; then
  if [ "$ENABLE_RNDIS_MS_IAD" = "true" ]; then
    log "RNDIS MS IAD patch already applied, keeping it"
  else
    log "reverting RNDIS MS IAD patch (ENABLE_RNDIS_MS_IAD=false)"
    patch -p1 -R < patch/rndis-ms-iad_desc.patch
  fi
elif [ "$ENABLE_RNDIS_MS_IAD" = "true" ]; then
  log "applying RNDIS MS IAD patch patch/rndis-ms-iad_desc.patch"
  patch -p1 < patch/rndis-ms-iad_desc.patch
else
  log "skipping RNDIS patch (not applied, stock OpenStick ACM enumeration)"
fi

# --- 4. kernel config ------------------------------------------------------------
if [ "$USE_REBUILD_CONFIG" = "true" ] && [ -f "$SRC/kernel-rebuild.config" ]; then
  log "using kernel-rebuild.config (full .config exported from a known-good local build)"
  cp "$SRC/kernel-rebuild.config" .config
  make olddefconfig
else
  [ "$USE_REBUILD_CONFIG" = "true" ] && \
    log "!! kernel-rebuild.config not found at $SRC, falling back to plain msm8916_defconfig"
  log "using msm8916_defconfig"
  make msm8916_defconfig
fi
KREL="$(make -s kernelrelease)"
echo "KREL=$KREL" > "$STAGE/kernelrelease.txt"
log "kernel release: $KREL"

if [ -n "${EXTRA_CONFIG:-}" ]; then
  log "applying extra kernel config: $EXTRA_CONFIG"
  for cfg in $EXTRA_CONFIG; do
    cfg="${cfg%%#*}"
    [ -z "$cfg" ] && continue
    case "$cfg" in
      CONFIG_*=y) scripts/config --enable  "${cfg%=*}" ;;
      CONFIG_*=m) scripts/config --module  "${cfg%=*}" ;;
      CONFIG_*=n) scripts/config --disable "${cfg%=*}" ;;
      *) log "ignoring unrecognized config entry: $cfg" ;;
    esac
  done
  make olddefconfig
fi

# --- 5+6. kernel build + debs, possibly served from a checkpoint ---------------
# checkpoint = compiled kernel + debs stored BEFORE the base-pack stage, so a
# rerun that failed later (download/chroot/...) skips the compile entirely
CHECKPOINT="$CACHE/checkpoint"
FPRINT="$( { printf '%s\n' "$DEVICE" "$ENABLE_RNDIS_MS_IAD" "$EXTRA_CONFIG"; \
             if [ "$USE_REBUILD_CONFIG" = "true" ] && [ -f "$SRC/kernel-rebuild.config" ]; then \
               sha256sum "$SRC/kernel-rebuild.config"; else echo "defconfig"; fi; \
             sha256sum "$SRC_COPY/patch/rndis-ms-iad_desc.patch"; \
           } | sha256sum | cut -d' ' -f1 )"

IMAGE_GZ=arch/arm64/boot/Image.gz
DTB=arch/arm64/boot/dts/qcom/msm8916-handsome-openstick-"$DEVICE".dtb

REUSE=false
if [ "${FULL_REBUILD:-false}" != "true" ] && [ -f "$CHECKPOINT/fingerprint" ] \
   && [ "$(cat "$CHECKPOINT/fingerprint")" = "$FPRINT" ] \
   && [ -f "$CHECKPOINT/$(basename "$IMAGE_GZ")" ] \
   && [ -f "$CHECKPOINT/$(basename "$DTB")" ] \
   && [ -n "$(ls "$CHECKPOINT"/linux-*.deb 2>/dev/null)" ] \
   && ! find "$SRC" \( -path "$SRC/.git" -o -path "$SRC/build" -o -path "$SRC/workspace" \) -prune \
        -o -type f -newer "$CHECKPOINT/.stamp" -print -quit | grep -q .; then
  REUSE=true
fi

if [ "$REUSE" = "true" ]; then
  log "checkpoint hit: reusing previous kernel build (inputs unchanged)"
  # restore the artifacts where the later stages expect them
  cp -f "$CHECKPOINT"/linux-*.deb "$BUILD/"
  mkdir -p "$SRC_COPY/$(dirname "$IMAGE_GZ")" "$SRC_COPY/$(dirname "$DTB")"
  cp -f "$CHECKPOINT/$(basename "$IMAGE_GZ")" "$SRC_COPY/$IMAGE_GZ"
  cp -f "$CHECKPOINT/$(basename "$DTB")" "$SRC_COPY/$DTB"
else
  if [ -f "$CHECKPOINT/fingerprint" ]; then
    log "no usable checkpoint (inputs changed or FULL_REBUILD), building from scratch"
  fi
  log "building kernel (make -j$(nproc))"
  make -j"$(nproc)"
  make dtbs
  [ -f "$IMAGE_GZ" ] || die "missing $IMAGE_GZ, kernel build may be incomplete"
  [ -f "$DTB" ] || die "missing $DTB, check the device name or the *.dts files next to it"

  log "packaging debs (make-kpkg kernel_image kernel_headers)"
  fakeroot make-kpkg --initrd --cross-compile "${CROSS_COMPILE}" --arch arm64 \
    kernel_image kernel_headers
  # debs are generated one level above the source dir: $BUILD/linux-*.deb
  debs=("$BUILD"/linux-*.deb)
  [ -e "${debs[0]}" ] || die "no deb packages found"
  log "debs:${debs[*]}"

  log "saving checkpoint to $CHECKPOINT (before the base-pack stage)"
  rm -rf "$CHECKPOINT" && mkdir -p "$CHECKPOINT"
  cp -f "${debs[@]}" "$CHECKPOINT/"
  cp -f "$IMAGE_GZ" "$CHECKPOINT/$(basename "$IMAGE_GZ")"
  cp -f "$DTB" "$CHECKPOINT/$(basename "$DTB")"
  cp -f "$STAGE/kernelrelease.txt" "$CHECKPOINT/"
  echo "$FPRINT" > "$CHECKPOINT/fingerprint"
  touch "$CHECKPOINT/.stamp"
fi
# debs must exist for the chroot stage in both branches
debs=("$BUILD"/linux-*.deb)
[ -e "${debs[0]}" ] || die "no deb packages found"
log "debs:${debs[*]}"

# --- 7. prepare qemu binfmt (running arm64 inside chroot) --------------------------
log "registering aarch64 binfmt (qemu-user-static)"
# inside the container /proc/sys/fs/binfmt_misc usually does not exist yet
mkdir -p /proc/sys/fs/binfmt_misc 2>/dev/null || true
if ! mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null \
   && [ ! -f /proc/sys/fs/binfmt_misc/register ]; then
  die "binfmt_misc unavailable (container must run with privileged: true, see compose.yml.example)"
fi
update-binfmts --enable qemu-aarch64 || true

# --- 8. download and unpack the OpenStick base pack --------------------------------
# the cached zip is reused only after passing an integrity check (unzip -t);
# a truncated download from an earlier run must not be trusted forever
if [ -f "$CACHE/debian.zip" ] && unzip -t "$CACHE/debian.zip" >/dev/null 2>&1; then
  log "using cached base pack $CACHE/debian.zip"
else
  if [ -f "$CACHE/debian.zip" ]; then
    log "cached base pack is corrupt, discarding and re-downloading"
    rm -f "$CACHE/debian.zip"
  fi
  log "downloading base pack to $CACHE/debian.zip ($BASE_URL)"
  # download under a .part name and rename on success, so an interrupted run
  # never leaves a half-written file under the final cache name
  if ! wget -q --show-progress -O "$CACHE/debian.zip.part" "$BASE_URL"; then
    rm -f "$CACHE/debian.zip.part"
    die "base pack download failed: $BASE_URL"
  fi
  mv -f "$CACHE/debian.zip.part" "$CACHE/debian.zip"
  unzip -t "$CACHE/debian.zip" >/dev/null 2>&1 \
    || die "downloaded base pack failed the integrity check; re-run to try again"
fi
rm -rf "$BUILD/base" && mkdir -p "$BUILD/base"
unzip -q -o "$CACHE/debian.zip" -d "$BUILD/base"
# the base pack keeps rootfs.img under a debian/ subdirectory
ROOTFS="$(find "$BUILD/base" -type f -iname 'rootfs.img' -print -quit)"
[ -n "$ROOTFS" ] || die "rootfs.img not found in the base pack"
log "rootfs: $ROOTFS"

# --- 9. convert and mount the rootfs -----------------------------------------------
log "converting and mounting rootfs ($ROOTFS)"
# work files live in the named volume (a real host filesystem); loop mounts
# may still be unavailable on some docker setups, so fall back to extracting
# the ext4 image with debugfs -- no mount required for the fallback path
ROOTFS_WORK="$CACHE/rootfs-work"
rm -rf "$ROOTFS_WORK" && mkdir -p "$ROOTFS_WORK"
# OpenStick rootfs.img is Android sparse; fall back to a plain copy when it is not
if ! simg2img "$ROOTFS" "$ROOTFS_WORK/root.img" 2>/dev/null; then
  log "rootfs.img is not sparse, using the file as-is"
  cp -f "$ROOTFS" "$ROOTFS_WORK/root.img"
fi
# privileged containers do not ship /dev/loop* nodes; create them so that
# mount -o loop / losetup can work (mknod is allowed when privileged)
[ -c /dev/loop-control ] || mknod /dev/loop-control c 10 237 2>/dev/null || true
for i in 0 1 2 3 4 5 6 7; do
  [ -b "/dev/loop$i" ] || mknod "/dev/loop$i" b 7 "$i" 2>/dev/null || true
done
ROOT_MOUNTED=false
ROOTMNT="$ROOTFS_WORK/rootmnt"
mkdir -p "$ROOTMNT"
if mount -o loop "$ROOTFS_WORK/root.img" "$ROOTMNT" 2>/dev/null; then
  ROOT_MOUNTED=true
  log "rootfs loop-mounted at $ROOTMNT"
else
  log "loop mount unavailable, extracting rootfs with debugfs instead"
  ROOTMNT="$ROOTFS_WORK/extracted"
  mkdir -p "$ROOTMNT"
  debugfs -R "rdump / $ROOTMNT" "$ROOTFS_WORK/root.img" >/dev/null 2>&1 \
    || die "debugfs extraction failed -- is root.img a valid ext4 image?"
  # recreate the device nodes dpkg/initramfs-tools expect in the extraction
  mkdir -p "$ROOTMNT/dev"
  mknod "$ROOTMNT/dev/null"     c 1 3  2>/dev/null || true
  mknod "$ROOTMNT/dev/zero"     c 1 5  2>/dev/null || true
  mknod "$ROOTMNT/dev/full"     c 1 7  2>/dev/null || true
  mknod "$ROOTMNT/dev/random"   c 1 8  2>/dev/null || true
  mknod "$ROOTMNT/dev/urandom"  c 1 9  2>/dev/null || true
  mknod "$ROOTMNT/dev/tty"      c 5 0  2>/dev/null || true
  mknod "$ROOTMNT/dev/console"  c 5 1  2>/dev/null || true
fi
# bind-mount targets must exist inside the image
mkdir -p "$ROOTMNT/dev/pts"
mount --bind /proc "$ROOTMNT/proc"
mount --bind /sys  "$ROOTMNT/sys"
mount --bind /dev  "$ROOTMNT/dev"
mount --bind /dev/pts "$ROOTMNT/dev/pts"

# --- 10. chroot: install the new kernel, generate a matching initrd ------------------
log "installing the new kernel debs inside chroot"
cp "${debs[@]}" "$ROOTMNT/tmp/"
chroot "$ROOTMNT" /bin/bash -c '
  set -e
  export DEBIAN_FRONTEND=noninteractive
  # first purge the stock kernel debs (their /boot initrd/vmlinuz go away too)
  dpkg -l | grep -E "linux-(headers|image)" | awk "{print \$2}" | xargs -r dpkg -P
  dpkg -i /tmp/linux-image-*.deb /tmp/linux-headers-*.deb
'
# the old kernels were purged above, so only the new initrd should be left
INITRD="$(ls "$ROOTMNT"/boot/initrd.img-${KREL}* | head -1)"
[ -n "${INITRD:-}" ] || die "initrd.img-${KREL}* not found in $ROOTMNT/boot after chroot install (check the step above)"
log "initrd obtained: $INITRD"
cp "$INITRD" "$STAGE/initrd.img"

# --- 11. unmount and clean up --------------------------------------------------------
umount "$ROOTMNT/dev/pts" 2>/dev/null || true
umount "$ROOTMNT/dev"     2>/dev/null || true
umount "$ROOTMNT/proc"    2>/dev/null || true
umount "$ROOTMNT/sys"     2>/dev/null || true
umount "$ROOTMNT"         2>/dev/null || true

# --- 12. assemble the boot image -------------------------------------------------------
log "assembling boot image (mkbootimg)"
cd "$STAGE"
# Image.gz concatenated with the dtb (kernel has built-in appended-dtb support)
cat "$SRC_COPY/$IMAGE_GZ" "$SRC_COPY/$DTB" > kernel-dtb
mkbootimg \
  --base 0x80000000 \
  --kernel_offset 0x00080000 \
  --ramdisk_offset 0x02000000 \
  --tags_offset 0x01e00000 \
  --pagesize 2048 \
  --second_offset 0x00f00000 \
  --ramdisk initrd.img \
  --cmdline "${CMDLINE}" \
  --kernel kernel-dtb \
  -o "$DEVICE-boot.img"

# --- 13. collect artifacts into /dist ---------------------------------------------------
log "collecting artifacts into $OUT"
cp "$STAGE/$DEVICE-boot.img" "$OUT/"
cp "$STAGE/initrd.img"       "$OUT/"
cp "$STAGE/kernelrelease.txt" "$OUT/"
cp "$SRC_COPY/$IMAGE_GZ"     "$OUT/Image.gz"
cp "$SRC_COPY/$DTB"          "$OUT/$(basename "$DTB")"
cp "$BUILD"/linux-*.deb      "$OUT/"

cat > "$OUT/README.txt" <<EOF
built for: $DEVICE
  kernel: $KREL
  RNDIS MS IAD patch: $ENABLE_RNDIS_MS_IAD
  boot cmdline: $CMDLINE
EOF

log "done, artifacts in $OUT:"
ls -lh "$OUT"
