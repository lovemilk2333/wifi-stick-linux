# OpenStick GitHub Actions build files

`msm8916.config` is the known-working configuration copied from the existing
OpenStick kernel build environment. The workflow first applies this file and
runs `make olddefconfig`, so new kernel configuration symbols receive their
upstream defaults without silently discarding the established configuration.

`configure-rootfs.sh` runs inside the ARM64 Debian root filesystem through
QEMU. It configures the target's package sources and installs the freshly built
kernel packages.

The workflow packages the same kernel and root filesystem for these devices:

- `sp970`
- `ufi001b`
- `ufi001c`
- `uz801`

The artifact contains one shared `rootfs.img`, four `<device>-boot.img` files,
and `SHA256SUMS`.
