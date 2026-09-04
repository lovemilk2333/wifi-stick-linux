# GitHub Actions build

The workflow is at `.github/workflows/build-openstick-kernel.yml`. It targets
GitHub's `ubuntu-24.04` runner and builds all four MSM8916 OpenStick variants.

Run it from the repository's **Actions** tab by choosing **Build OpenStick
kernel images** and clicking **Run workflow**. On completion, download the
`openstick-kernel-<commit>` artifact. It contains four device-specific boot
images, the common root filesystem image, and SHA-256 checksums.

The first successful run populates the `ccache` cache. Later runs restore that
cache automatically; cache hits depend on the compiler and the kernel's
preprocessed source, so changed files are rebuilt normally.
