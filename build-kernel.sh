#!/bin/bash
set -e

# Set architecture and cross-compilation settings
ARCH=${ARCH:-x86_64}
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
if [ -f "/input/linux-upstream_6.8.12.orig.tar.gz" ]; then
    echo "Using provided kernel source tarball"
    cp "/input/linux-upstream_6.8.12.orig.tar.gz" .
    tar xf linux-upstream_6.8.12.orig.tar.gz
    cd linux-upstream-6.8.12
else
    echo "Cloning kernel source from git"
    git clone --depth 1 --branch v6.8.12 https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
    cd linux
fi

# Configure kernel
echo -e "\n=== Step 2: Configuring kernel ==="
echo "Running defconfig..."
make ARCH=$ARCH defconfig

echo "Running localmodconfig..."
make ARCH=$ARCH localmodconfig

echo "Enabling debug options..."
scripts/config --enable DEBUG_INFO \
               --enable DEBUG_INFO_DWARF5 \
               --enable DEBUG_INFO_BTF \
               --enable DEBUG_KERNEL \
               --enable DEBUG_MISC \
               --enable DEBUG_SECTION_MISMATCH \
               --enable DEBUG_STACK_USAGE \
               --enable DEBUG_VM \
               --enable DEBUG_VIRTUAL \
               --enable DEBUG_WX \
               --enable DEBUG_WORKQUEUE \
               --enable DEBUG_WW_MUTEX_SLOWPATH \
               --enable DEBUG_WARNINGS \
               --enable DEBUG_WRITABLE \
               --enable DEBUG_XARRAY \
               --enable DEBUG_ZBOOT \
               --enable DEBUG_ZONE_DMA \
               --enable DEBUG_ZONE_DMA32 \
               --enable DEBUG_ZONE_HIGHMEM \
               --enable DEBUG_ZONE_NORMAL \
               --enable DEBUG_ZONE_MOVABLE \
               --enable DEBUG_ZONE_DEVICE \
               --enable DEBUG_ZONE_CMA \
               --enable DEBUG_ZONE_MEMORY \
               --enable DEBUG_ZONE_VMALLOC \
               --enable DEBUG_ZONE_KMALLOC \
               --enable DEBUG_ZONE_SLAB \
               --enable DEBUG_ZONE_PAGE \
               --enable DEBUG_ZONE_IO \
               --enable DEBUG_ZONE_DMA_COHERENT \
               --enable DEBUG_ZONE_DMA_NONCOHERENT \
               --enable DEBUG_ZONE_DMA_WC \
               --enable DEBUG_ZONE_DMA_UNCACHED \
               --enable DEBUG_ZONE_DMA_CACHEABLE \
               --enable DEBUG_ZONE_DMA_NONCACHEABLE \
               --enable DEBUG_ZONE_DMA_WRITEBACK \
               --enable DEBUG_ZONE_DMA_WRITETHROUGH \
               --enable DEBUG_ZONE_DMA_WRITECOMBINE \
               --enable DEBUG_ZONE_DMA_NONCOHERENT_WC \
               --enable DEBUG_ZONE_DMA_NONCOHERENT_UNCACHED \
               --enable DEBUG_ZONE_DMA_NONCOHERENT_CACHEABLE \
               --enable DEBUG_ZONE_DMA_NONCOHERENT_NONCACHEABLE \
               --enable DEBUG_ZONE_DMA_NONCOHERENT_WRITEBACK \
               --enable DEBUG_ZONE_DMA_NONCOHERENT_WRITETHROUGH \
               --enable DEBUG_ZONE_DMA_NONCOHERENT_WRITECOMBINE

# Build kernel
echo -e "\n=== Step 3: Building kernel ==="
echo "Building kernel with ARCH=$ARCH..."
time make ARCH=$ARCH -j$(nproc)

# Build Debian packages
echo -e "\n=== Step 4: Building Debian packages ==="
echo "Building kernel packages..."
time make -f debian/rules binary

# Move build artifacts
echo -e "\n=== Step 5: Moving build artifacts ==="
echo "Moving build artifacts to output directory..."
mv ../*.deb /output/
mv ../*.buildinfo /output/
mv ../*.changes /output/

echo -e "\n=== Build complete ==="
echo "Output files are in the output directory." 