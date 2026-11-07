# GitHub Actions build

The workflow is at `.github/workflows/build-openstick-kernel.yml`. It targets
GitHub's `ubuntu-24.04` runner and builds all four MSM8916 OpenStick variants.
The build steps live in the reusable workflow
`.github/workflows/build-openstick-kernel-build.yml`.

Run it from the repository's **Actions** tab by choosing **Build OpenStick
kernel images** and clicking **Run workflow**.

## Build modes

The `only_build_kernel` checkbox selects what the run produces:

| Mode | `only_build_kernel` | Artifacts |
| --- | --- | --- |
| Normal | `false` | Per-device `<device>-boot-<sha>` (boot image + kernel + dtb + initrd), `deb-packages-<sha>`, `rootfs-<sha>` |
| Kernel-only | `true` | Per-device `<device>-boot-<sha>` (boot image + kernel + dtb + initrd), `deb-packages-<sha>`, `openstick-kernel-only-<sha>` (raw `Image.gz` + dtbs) |

Kernel-only mode still downloads the OpenStick root filesystem, because its
`/boot/initrd.img` is the ramdisk embedded in every boot image. It only skips
producing and uploading the shared `rootfs.img`.

GitHub Actions cannot show or hide `workflow_dispatch` inputs based on another
input, so the form always shows every option. The root filesystem options still
run while preparing the initrd, but they only affect the rootfs artifact, which
kernel-only mode does not produce. `apt_mirror` is still needed to refresh the
rootfs before the initrd is regenerated.

The first successful run populates the `ccache` cache. Later runs restore that
cache automatically; cache hits depend on the compiler and the kernel's
preprocessed source, so changed files are rebuilt normally.
