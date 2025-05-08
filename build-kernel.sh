#!/bin/bash
set -e

# Set architecture and cross-compilation settings
ARCH=${ARCH:-x86_64}
KERNEL_TAG=${KERNEL_TAG:-6.8.0-60.63}

# Set source directory and tarfile names
SRC_DIR="Ubuntu-${KERNEL_TAG}-src"
SRC_TARBALL="Ubuntu-${KERNEL_TAG}-src.tar.xz"

# Disable treating warnings as errors
export KCFLAGS="-Wno-error"

if [ "$ARCH" = "arm64" ]; then
    export CROSS_COMPILE=aarch64-linux-gnu-
    export ARCH=arm64
fi

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
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Get kernel source
echo "=== Step 1: Preparing kernel source ==="
if [ -f "/input/${SRC_TARBALL}" ]; then
    echo "Using provided kernel source tarball"
    tar xf "/input/${SRC_TARBALL}"
else
    echo "Cloning kernel source from Ubuntu repository (version: $KERNEL_TAG)"
    git -c http.sslVerify=false clone --depth 1 --branch Ubuntu-${KERNEL_TAG} git://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/noble ${SRC_DIR}
    # Create source tarball with parallel xz compression
    echo "Creating source tarball with parallel xz compression..."
    tar cf - ${SRC_DIR} | xz -T0 -9 > ${SRC_TARBALL}
    mv ${SRC_TARBALL} /output/
fi

cd ${SRC_DIR}

# Configure kernel
echo -e "\n=== Step 2: Configuring kernel ==="
echo "Running defconfig..."
make ARCH=$ARCH defconfig

echo "Running localmodconfig..."
make ARCH=$ARCH localmodconfig

# Do not stop the build on warnings
scripts/config -d CONFIG_WERROR

# Build kernel
echo -e "\n=== Step 3: Building kernel ==="
echo "Building kernel with ARCH=$ARCH..."
time make ARCH=$ARCH -j$(nproc)

# Build Debian packages
echo -e "\n=== Step 4: Building Debian packages ==="
echo "Building kernel packages..."
time make ARCH=$ARCH -j$(nproc) bindeb-pkg

# Move build artifacts
echo -e "\n=== Step 5: Moving build artifacts ==="
echo "Moving build artifacts to output directory..."
mv ../*.deb /output/
mv ../*.buildinfo /output/
mv ../*.changes /output/

echo -e "\n=== Build complete ==="
echo "Output files are in the output directory."
