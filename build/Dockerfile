# Build image for UFI device kernels.
# Base image is Ubuntu 20.04: kernel-rebuild.config was generated with
# gcc-9.4, exactly the default cross compiler in focal.
#
# Freshness contract (what is "latest" and what is not):
#   * The image bakes in ONLY this Dockerfile, build.sh and the env defaults
#     below; run with --build to pick up changes there (few steps, cheap).
#   * kernel-rebuild.config, patch/ and the kernel sources are bind-mounted
#     from the repo root at /source and read at every container start.
#   * The env defaults below are overridden by compose.yml at creation time.
FROM ubuntu:20.04

# env defaults; overridable with compose or `docker run -e`
ENV DEBIAN_FRONTEND=noninteractive \
    ARCH=arm64 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    DEVICE=ufi001c \
    ENABLE_RNDIS_MS_IAD=true \
    USE_REBUILD_CONFIG=true \
    EXTRA_CONFIG="" \
    APT_SOURCE="" \
    APT_SECURITY_SOURCE="" \
    ENABLE_APT_SRC=false \
    BASE_URL="https://github.com/OpenStick/OpenStick/releases/download/v1/debian.zip" \
    CMDLINE="earlycon root=PARTUUID=a7ab80e8-e9d1-e8cd-f157-93f69b1d141e console=ttyMSM0,115200 no_framebuffer=true rw"

WORKDIR /source

COPY build.sh /build.sh
RUN chmod +x /build.sh

ENTRYPOINT ["/build.sh"]
# runs the full build by default; `docker compose run --rm <service> bash`
# drops into an interactive shell instead
CMD ["build"]
