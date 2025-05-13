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

# Verify input/output directories
if [ ! -d "/output" ] || [ ! -w "/output" ]; then
  echo "Error: /output directory is not writable"
  exit 1
fi

if [ ! -d "/input" ] || [ ! -r "/input" ]; then
  echo "Error: /input directory is not readable"
  exit 1
fi

# Define paths and filenames
BUILD_DIR="/home/builder/kernel-build"
SRC_DIR="${KERNEL_TAG}-src"
SRC_TARBALL="${KERNEL_TAG}-src.tar.xz"

echo "=== Step 1: Creating kernel build directory ==="
# Create build directory
if [ -d "$BUILD_DIR" ]; then
  echo "Old build directory found. Deleting"
  rm -rf "$BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Get kernel source
echo -e "\n=== Step 2: Preparing kernel source ==="
if [ -f "/input/${SRC_TARBALL}" ]; then
  echo "Using provided kernel source tarball"
  tar xf "/input/${SRC_TARBALL}"
else
  echo "Cloning kernel source from Ubuntu repository (version: $KERNEL_TAG)"
  git -c http.sslVerify=false clone --depth 1 --branch ${KERNEL_TAG} "${KERNEL_SOURCE}" "${BUILD_DIR}/${SRC_DIR}"
fi
SRC_TAR_DIR="/output/kernel-source"
SRC_TAR_DIR_ORIG="${SRC_TAR_DIR}/original"
echo "Compressing original sources to ${SRC_TAR_DIR_ORIG}"
mkdir -p "${SRC_TAR_DIR_ORIG}"
tar cf - ${SRC_DIR} | xz -T0 -9 > "${SRC_TAR_DIR_ORIG}/${SRC_TARBALL}"


cd "${BUILD_DIR}/${SRC_DIR}"

echo -e "\n=== Step 3: Patching kernel source ==="
for subdir in "${KERNEL_TAG}" "all"; do
  PATCH_DIR="/input/patches/${subdir}"
  if [ -d "${PATCH_DIR}" ]; then
    find "${PATCH_DIR}" -type f | while read patchfile; do
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
done

# Configure kernel
echo -e "\n=== Step 4: Configuring kernel ==="
CONFIG_SRC="/input/config-${KERNEL_TAG}-${ARCH}"
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

# Create tarball from modified sources with parallel xz compression
echo -e "\n=== Step 5: Creating source tarball with parallel xz compression ==="
cd "$BUILD_DIR"
SRC_TAR_DIR_MOD="${SRC_TAR_DIR}/modified"
mkdir -p "${SRC_TAR_DIR_MOD}"
echo "Compressing modified sources to ${SRC_TAR_DIR_MOD}"
tar cf - ${SRC_DIR} | xz -T0 -9 > "${SRC_TAR_DIR_MOD}/${SRC_TARBALL}"
cd "${BUILD_DIR}/${SRC_DIR}"

# Build kernel
echo -e "\n=== Step 6: Building kernel and deb packages ==="
echo "Building kernel packages with ARCH=$ARCH..."
time make $KMAKE_OPTS -j$(nproc) deb-pkg

# Move build artifacts
echo -e "\n=== Step 7: Moving build artifacts ==="
echo "Moving build artifacts to output directory..."
ls -al "${BUILD_DIR}"
mv -v "${BUILD_DIR}"/*.deb /output/
mv -v "${BUILD_DIR}"/*.buildinfo /output/
mv -v "${BUILD_DIR}"/*.changes /output/

echo -e "\n=== Build complete ==="
echo "Output files are in the output directory."
