# Linux Kernel Cross-Compilation Docker Image

This Docker image provides an environment for cross-compiling Linux kernel packages for both arm64 and amd64 architectures.

## Prerequisites

- Docker installed on your system
- Sufficient disk space (at least 20GB recommended)
- Sufficient RAM (at least 8GB recommended)

## Building the Docker Image

```bash
docker build -t kernel-builder .
```

## Usage

### Building for amd64 (interchangable with x86\_64

```bash
docker run --rm -v $(pwd)/output:/output -eARCH="amd64" kernel-builder
```

### Building for arm64

```bash
docker run --rm -v $(pwd)/output:/output -eARCH="arm64" kernel-builder
```

### Customizing the Build

You can customize the build by setting environment variables:

```bash
docker run --rm \
  -v $(pwd)/output:/output \
  -e KERNEL_TAG=v6.8 \
  -e KERNEL_SOURCE=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git \
  kernel-builder arm64
```

## Output

The built Debian packages will be available in the `output` directory on your host system. The packages include:

- linux-image-\*.deb: The kernel image package
- linux-headers-\*.deb: The kernel headers package
- linux-libc-dev-\*.deb: The kernel development package

## Notes

- The build process may take several hours depending on your system's resources
- Make sure you have enough disk space in the output directory
- You can provide your own config by supplying a file in the input directory named `config-${KERNEL_TAG}-${ARCH}`
  - The supplied config file will be olddefconfig'd because we don't trust you
- The build uses the default kernel configuration (defconfig)
- Patches found in `/input/patches` will be applied to the kernel source before configuration
  - The `/input/patches/all` subdirectory will be processed for all build tags
  - For patches intended for specific build tags use `/input/patches/${KERNEL_TAG}`
  - Files directly in `/input/patches`, or files beginning with a period will not be processed
