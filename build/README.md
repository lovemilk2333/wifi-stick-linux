# UFI kernel builder (container)

Builds the Debian firmware kernel + boot.img for UFI devices (OpenStick
msm8916 family) inside an Ubuntu 20.04 container. Output goes to `/dist`
(host: `build/dist`).

```
build/
├── Dockerfile           # ubuntu:20.04, env defaults, entrypoint
├── build.sh             # the whole build flow (entrypoint)
├── compose.yml.example  # copy to compose.yml and adjust
├── README.md
└── dist/                # artifacts land here (bind-mounted to /dist)
```

## One-shot build

```sh
cd build
cp compose.yml.example compose.yml   # first time only
sudo docker compose run --build --rm ufi-build
```

Artifacts in `build/dist/`: `<device>-boot.img`, `initrd.img`, `Image.gz`,
`<device>.dtb`, `linux-image-*.deb`, `linux-headers-*.deb`,
`kernelrelease.txt`, `README.txt`.

Each `run --rm` starts a fresh container, so the toolchain is reinstalled
every time (which is what makes `APT_SOURCE` matter). `--build` rebuilds the
image first; the Dockerfile has only a few steps, so this is cheap and
guarantees the image always carries the latest `build.sh`.

### What is "latest" and what is not

Only `build/Dockerfile` and `build/build.sh` are baked into the image (via
`--build`). Everything else is read at container start, so edits apply
without any rebuild:

- `kernel-rebuild.config`, `patch/`, the kernel sources -> bind-mounted from
  the repo root (`/source`, read-only)
- `DEVICE`, `ENABLE_RNDIS_MS_IAD`, mirrors, ... -> environment from
  `compose.yml` (set at container creation)
- artifacts -> `build/dist/` (`/dist`)

## Iterate on one container (install once, then rebuild)

Keep a container alive without starting a build, then run builds inside it:

```sh
# build the image once, then start a detached "workbench" container
# (does NOT build)
sudo docker compose run -d --name ufi-build ufi-build wait

# run/rerun a build whenever you change DEVICE/config/patches
# (kernel-rebuild.config and patch/ are picked up from /source every time)
sudo docker exec -it ufi-build /build.sh build

# stop and remove it when done
sudo docker stop ufi-build && sudo docker rm ufi-build
```

Notes:

- The toolchain is installed on the first `build.sh build` and kept in the
  container's writable layer afterwards.
- The kernel build tree lives in the named volume `ufi-build-src`
  (`/build/src`) and survives between runs; the source sync keeps file
  mtimes, so `make` recompiles only what changed (config toggles included).
  Set `FULL_REBUILD=true` for a clean compile.
- A build checkpoint (kernel + debs + dtb) is saved to the cache volume
  right before the base-pack stage (`/build/cache/checkpoint`). When a run
  fails later (base-pack download, chroot, ...), the next run with
  unchanged inputs skips the compile entirely and resumes from there. The
  checkpoint is keyed by device/config/patch fingerprints plus source-file
  freshness and invalidates automatically on any change.
- So the fastest loop is: workbench container + repeated
  `sudo docker exec ufi-build /build.sh build` -- toolchain once, kernel
  recompiled incrementally, the 376 MB base pack and the converted root.img
  reused from the `ufi-build-cache` volume.
- `docker compose up -d` does NOT fit here: it starts the container with
  the default `build` command, so the full build runs once automatically
  and the container exits when it finishes.
- Environment variables (device, RNDIS, mirror, ...) are fixed when the
  container is created; to switch them, recreate it with `-e`, e.g.
  `sudo docker compose run -d --name ufi-build -e DEVICE=sp970 ufi-build wait`.

## Options

| env                     | default | meaning                                                    |
| ----------------------- | ------- | ---------------------------------------------------------- |
| `DEVICE`                | ufi001c | target device: ufi001b / ufi001c / sp970 / uz801           |
| `ENABLE_RNDIS_MS_IAD`   | true    | apply `patch/rndis-ms-iad_desc.patch` before building      |
| `USE_REBUILD_CONFIG`    | true    | build with `kernel-rebuild.config` (falls back to defconfig if missing) |
| `EXTRA_CONFIG`          | ""      | extra kernel config entries, space separated (`CONFIG_X=y CONFIG_Y=m`) |
| `FULL_REBUILD`          | false   | wipe the kernel build tree first (full clean compile) |
| `APT_SOURCE`            | ""      | mirror for the regular archive: bare host or full URL, e.g. `mirrors.nju.edu.cn` or `https://mirrors.aliyun.com/ubuntu`; empty = official |
| `APT_SECURITY_SOURCE`   | ""      | security-suite mirror, full URL; empty = same as `APT_SOURCE`. Mirrors with a separate `/ubuntu-security` (USTC, TUNA) must set it |
| `ENABLE_APT_SRC`        | false   | write active deb-src (source) lines: true / false (commented) |
| `BASE_URL`              | OpenStick v1 debian.zip | base pack download URL |
| `CMDLINE`               | tutorial value | kernel cmdline for mkbootimg |

## Requirements

- `network_mode: host` in compose.yml (downloads/mirrors go out through the
  host's connection).
- `privileged: true` in compose.yml (qemu chroot needs mount + binfmt_misc).
- Repo root mounted read-only at `/source`; the build runs on an
  in-container copy, so the host repo stays clean.
- `kernel-rebuild.config` at the repo root must exist (or be committed) for
  the default config path.

## Artifacts & flashing

### Artifacts in build/dist

| file                     | what it is                                    | needed to swap the kernel? |
| ------------------------ | --------------------------------------------- | -------------------------- |
| `<device>-boot.img`      | kernel + dtb + matching initrd, already       | **yes, this is the one**   |
|                          | assembled for mkbootimg                       |                            |
| `linux-image-*.deb`      | kernel deb incl. all `/lib/modules/<ver>`     | recommended (see below)    |
| `linux-headers-*.deb`    | headers for building out-of-tree modules      | only if you build modules  |
| `initrd.img` / `Image.gz` / `*.dtb` | raw parts of the boot.img        | no (only to re-assemble)   |
| `kernelrelease.txt`      | kernel release string (e.g.                   | reference only             |
|                          | `5.15.0-handsomekernel-dezigenb-rebuild`)     |                            |

### Fresh device (from stock/Android firmware)

> **Back up first.** Enter EDL/9008 mode (hold the reset button while
> plugging in USB, or `adb reboot edl` once adb works) and dump the whole
> eMMC with <https://github.com/bkerler/edl>:
> `edl rl dumps-ufi001c --genxml` (restore with `edl qfil ...`).

1. From <https://github.com/OpenStick/OpenStick/releases> take `base.zip`
   and `debian.zip`.
2. Unzip `debian.zip`, then **copy our `build/dist/<device>-boot.img` over
   its `boot.img`** (rename it) -- it carries the freshly built kernel.
3. Boot the device into fastboot (`adb reboot bootloader`), run
   `base`/`flash.sh` (Windows: `flash.bat`), then `debian`/`flash.sh`.
   The device reboots into Debian (SSH root@192.168.68.1).

### Kernel-only replacement on an already-flashed device

The rootfs does NOT need touching: `<device>-boot.img` already contains the
new kernel, the device dtb and a matching initrd. Flash just the boot
partition:

```sh
# copy the image to the running device (root password is `1` on stock)
adb push ufi001c-boot.img /root/          # or scp to 192.168.68.1

# route A: fastboot
adb reboot bootloader
fastboot flash boot ufi001c-boot.img
fastboot reboot

# route B: dd from the running Debian (check the partition name first)
lsblk -o NAME,SIZE,PARTLABEL              # pick PARTLABEL=boot
dd if=/root/ufi001c-boot.img of=/dev/disk/by-partlabel/boot bs=4M conv=fsync
reboot

# verify
uname -r      # -> 5.15.0-handsomekernel-dezigenb-rebuild
```

### Matching loadable modules (recommended)

The initrd inside boot.img only carries the modules needed to boot. Once
the system runs, `modprobe` looks in the rootfs at
`/lib/modules/$(uname -r)/` -- which still holds the *stock* kernel's
modules if the rootfs was never touched. Modules built as `=m` (crypto,
nftables, ...) would then fail to load.

Install the image deb into the rootfs once (on the device, or via the
chroot flow): this lays down `/lib/modules/<ver>`, runs depmod and
generates a new initrd. No need to re-flash afterwards -- the boot
partition already boots the new kernel:

```sh
dpkg -i linux-image-5.15.0-handsomekernel-dezigenb-rebuild_*.deb
```

`linux-headers-*.deb` is only required to compile out-of-tree modules.

### Clean rebuilds

- Recompile from scratch but keep the 376 MB base pack cached:
  `sudo docker compose run --build --rm -e FULL_REBUILD=true ufi-build`
- Wipe every cache (build tree, base pack, checkpoint) and start from
  zero: `sudo docker compose down -v`, optionally
  `sudo docker rmi build-ufi-build`, then the normal build command.
