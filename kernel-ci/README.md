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

## QEMU test kernel

`qemu.config` builds a kernel for the QEMU `virt` machine, so the
`wifi-stick-usb-switcher` daemon can be exercised without an OpenStick on the
desk. It is driven by `.github/workflows/build-qemu-kernel.yml`, whose artifact
is `qemu-kernel-<sha>` containing `qemu-Image`, `qemu-Image.gz` and
`qemu-config`. **This kernel cannot be flashed to a stick**: it has no msm8916
support and no DTB, and everything it emits carries a `qemu-` prefix so it is
not mistaken for a device boot image.

It is based on `arch/arm64/configs/defconfig`, not on `msm8916.config`: the
device configuration is trimmed to a single SoC and disables the virtualisation
hardware QEMU provides. The deltas are small and deliberate.

| Option | Why |
| --- | --- |
| `USB_DUMMY_HCD=y` | The virtual UDC. The daemon takes the single entry in `/sys/class/udc`, which under QEMU can only be `dummy_udc.0` — without it there is no gadget to switch. |
| `USB_CONFIGFS=y` and friends | Built in rather than modular: the test image ships no `/lib/modules`, so anything left as `=m` is simply absent. `USB_CONFIGFS=y` also promotes every gadget function to `=y` through `select`, which costs nothing and leaves room to test modes beyond RNDIS and ADB. |
| `INPUT_UINPUT=y` | The virtual button the tests inject key events through. |
| `LEDS_USER=y` | `uleds` gives the daemon a `/sys/class/leds/<name>` to drive; QEMU `virt` has no GPIO and no real LED. |
| `VIRTIO_INPUT=y`, `HW_RANDOM_VIRTIO=y` | Optional extras: a host-driven keyboard, and entropy at boot. |
| `OVERLAY_FS=y` | Built in for convenience when composing test root filesystems. |
| `CONFIG_LOCALVERSION="-qemu"` | `uname -r` reports `5.15.0-qemu`, so a shell inside the guest is never ambiguous about which kernel it is running. |

`qemu-smoke-init.c` is a statically linked arm64 `/init` for a minimal
initramfs. The workflow boots the kernel it just built under
`qemu-system-aarch64 -M virt`, asserts the interfaces the test environment
depends on exist, then performs one real configfs gadget bind against
`dummy_udc.0`. It is a static C binary rather than a busybox shell because the
busybox available on the runner is x86_64 and would not execute inside the
guest; this way the check also downloads nothing. Set the `smoke_test` input to
false to skip it.

Both the build and the smoke test run locally too, given `bc` and
`aarch64-linux-gnu-gcc`:

```sh
cp kernel-ci/qemu.config .config
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" Image

mkdir -p smoke && aarch64-linux-gnu-gcc -static -O2 -o smoke/init kernel-ci/qemu-smoke-init.c
(cd smoke && find . -print0 | cpio --null -o -H newc --quiet | gzip -9) > smoke.cpio.gz
qemu-system-aarch64 -M virt -cpu cortex-a57 -m 1024 -smp 2 \
  -kernel arch/arm64/boot/Image -initrd smoke.cpio.gz \
  -append "console=ttyAMA0 earlycon=pl011,0x9000000 rdinit=/init panic=-1" \
  -nographic -no-reboot
```
