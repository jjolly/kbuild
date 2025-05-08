#!/bin/bash
set -e

# Set architecture and cross-compilation settings
ARCH=${ARCH:-x86_64}
CROSS_COMPILE=x86_64-linux-gnu-

if [ "x${ARCH}" == "xamd64" ]; then
  # Old habits die hard
  ARCH=x86_64
fi

if [ "x${ARCH}" == "xarm64" ]; then
  CROSS_COMPILE=aarch64-linux-gnu-
fi

KMAKE_OPTS="ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE"

# Set kernel source and version
KERNEL_SOURCE=${KERNEL_SOURCE:-git://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/noble}
KERNEL_TAG=${KERNEL_TAG:-Ubuntu-6.8.0-60.63}

# Set source directory and tarfile names
SRC_DIR="${KERNEL_TAG}-src"
SRC_TARBALL="${KERNEL_TAG}-src.tar.xz"

# Verify input/output directories
if [ ! -d "/output" ] || [ ! -w "/output" ]; then
  echo "Error: /output directory is not writable"
  exit 1
fi

if [ ! -d "/input" ] || [ ! -r "/input" ]; then
  echo "Error: /input directory is not readable"
  exit 1
fi

# Create build directory
BUILD_DIR="/home/builder/kernel-build"
if [ -d "$BUILD_DIR" ]; then
  rm -rf "$BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Get kernel source
echo "=== Step 1: Preparing kernel source ==="
if [ -f "/input/${SRC_TARBALL}" ]; then
  echo "Using provided kernel source tarball"
  tar xf "/input/${SRC_TARBALL}"
else
  echo "Cloning kernel source from Ubuntu repository (version: $KERNEL_TAG)"
  git -c http.sslVerify=false clone --depth 1 --branch ${KERNEL_TAG} "${KERNEL_SOURCE}" ${SRC_DIR}
  # Create source tarball with parallel xz compression
  echo "Creating source tarball with parallel xz compression..."
  tar cf - ${SRC_DIR} | xz -T0 -9 > ${SRC_TARBALL}
  mv ${SRC_TARBALL} /output/
fi

cd ${SRC_DIR}

if [ -d "/input/patches" ]; then
  find /input/patches -type f | while read patchfile; do
    # Skip "hidden" files
    if [[ $(basename "$patchfile") =~ ^[^.] ]]; then
      echo Patching with $patchfile
      if ! patch -p1 < "$patchfile"; then
        echo "Patching failed with $patchfile"
        exit 1
      fi
    fi
  done
fi

# Configure kernel
echo -e "\n=== Step 2: Configuring kernel ==="
CONFIG_SRC="/input/config-${ARCH}"
if [ -f "${CONFIG_SRC}" ]; then
  echo "Using config file ${CONFIG_SRC}"
  cp "${CONFIG_SRC}" .config
  echo "Running olddefconfig..."
  make $KMAKE_OPTS olddefconfig
else
  echo "No config provided, building defconfig"
  make $KMAKE_OPTS defconfig
fi

# Do not stop the build on warnings
# This is a problem with the x86_64 defconfig, and not arm64
scripts/config -d CONFIG_WERROR

# Build kernel
echo -e "\n=== Step 3: Building kernel ==="
echo "Building kernel with ARCH=$ARCH..."
time make $KMAKE_OPTS -j$(nproc)

# Build Debian packages
echo -e "\n=== Step 4: Building Debian packages ==="
echo "Building kernel packages..."
time make $KMAKE_OPTS -j$(nproc) bindeb-pkg

# Move build artifacts
echo -e "\n=== Step 5: Moving build artifacts ==="
echo "Moving build artifacts to output directory..."
mv ../*.deb /output/
mv ../*.buildinfo /output/
mv ../*.changes /output/

echo -e "\n=== Build complete ==="
echo "Output files are in the output directory."
