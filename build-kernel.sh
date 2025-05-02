#!/bin/bash
set -e

# Set defaults for environment variables
ARCH=${ARCH:-x86_64}
KERNEL_TAG=${KERNEL_TAG:-6.8.0-60.63}

# Set build environment
export DEBIAN_FRONTEND=noninteractive
export DEB_BUILD_OPTIONS="parallel=$(nproc)"

# Set cross-compilation settings for ARM64
if [ "$ARCH" = "arm64" ]; then
    export CROSS_COMPILE=aarch64-linux-gnu-
    export ARCH=arm64
fi

# Verify directories
echo "Verifying directories..."
if [ ! -d "/output" ]; then
    echo "Error: Output directory /output does not exist"
    exit 1
fi

if [ ! -w "/output" ]; then
    echo "Error: Output directory /output is not writable"
    exit 1
fi

if [ ! -d "/input" ]; then
    echo "Error: Input directory /input does not exist"
    exit 1
fi

# Create build directory
BUILD_DIR="/home/builder/kernel-build"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Set source directory and tarball names
SRC_DIR="Ubuntu-${KERNEL_TAG}-src"
SRC_TARBALL="Ubuntu-${KERNEL_TAG}-src.tar.xz"

# Check for source tarball in input directory first, then output directory
if [ -f "/input/$SRC_TARBALL" ]; then
    echo "Found kernel source tarball in input directory, extracting..."
    tar xf "/input/$SRC_TARBALL"
elif [ -f "/output/$SRC_TARBALL" ]; then
    echo "Found kernel source tarball in output directory, extracting..."
    tar xf "/output/$SRC_TARBALL"
else
    echo "No existing kernel source tarball found, cloning from repository..."
    # Clone kernel source
    git clone --depth 1 --branch Ubuntu-${KERNEL_TAG} git://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/noble "$SRC_DIR"

    # Create source tarball
    echo "Creating source tarball..."
    tar --exclude='.git' -cf - "$SRC_DIR" | xz -T0 -9 > "$SRC_TARBALL"
    # Move source tarball to output directory immediately
    echo "Moving source tarball to output directory..."
    mv "$SRC_TARBALL" /output/
fi

# Configure kernel
echo "Configuring kernel..."
cd "$SRC_DIR"
make ARCH=$ARCH defconfig
make ARCH=$ARCH localmodconfig

# Enable debug options
echo "Enabling debug options..."
scripts/config --enable DEBUG_KERNEL
scripts/config --enable DEBUG_INFO
scripts/config --enable DEBUG_INFO_DWARF5
scripts/config --enable GDB_SCRIPTS

# Build kernel packages
echo "Building kernel packages..."
make ARCH=$ARCH KCFLAGS="-Wno-error=address -Wno-error=parentheses -Wno-error=missing-prototypes" bindeb-pkg -j$(nproc)

# Copy build artifacts to a temporary directory
echo "Preparing build artifacts..."
TEMP_OUTPUT="/home/builder/output"
mkdir -p "$TEMP_OUTPUT"
mv ../*.deb "$TEMP_OUTPUT/"

# Move artifacts to the final output directory
echo "Moving artifacts to output directory..."
cp -r "$TEMP_OUTPUT"/* /output/

echo "Build complete. Output files are in the output directory." 