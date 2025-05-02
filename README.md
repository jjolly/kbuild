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

### Building for amd64

```bash
docker run --rm -v $(pwd)/output:/output kernel-builder amd64
```

### Building for arm64

```bash
docker run --rm -v $(pwd)/output:/output kernel-builder arm64
```

### Customizing the Build

You can customize the build by setting environment variables:

```bash
docker run --rm \
  -v $(pwd)/output:/output \
  -e KERNEL_VERSION=6.1.0 \
  -e KERNEL_SOURCE=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git \
  -e KERNEL_BRANCH=linux-6.1.y \
  kernel-builder arm64
```

## Output

The built Debian packages will be available in the `output` directory on your host system. The packages include:

- linux-image-*.deb: The kernel image package
- linux-headers-*.deb: The kernel headers package
- linux-libc-dev-*.deb: The kernel development package

## Notes

- The build process may take several hours depending on your system's resources
- Make sure you have enough disk space in the output directory
- The build uses the default kernel configuration (defconfig)
- For custom kernel configurations, you'll need to modify the build script 