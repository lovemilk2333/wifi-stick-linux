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
