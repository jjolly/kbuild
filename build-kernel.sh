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

KERNELRELEASE=${KERNELRELEASE:-6.8.0-60.63}

KMAKE_OPTS="ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE KERNELRELEASE=${KERNELRELEASE} -j$(nproc)"

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
# Tag may have extra slashes, so keep track of the source parent
SRC_PARENT_DIR="${SRC_DIR}/.."
SRC_TARFILE="${KERNEL_TAG}-src.tar.xz"

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
if [ -f "/input/${SRC_TARFILE}" ]; then
  echo "Using provided kernel source archive in tar file ${SRC_TARFILE}"
  tar xf "/input/${SRC_TARFILE}"
else
  echo "Source code archive not found at ${SRC_TARFILE}"
  echo "Cloning kernel source from Ubuntu repository (version: $KERNEL_TAG)"
  git -c http.sslVerify=false clone --depth 1 --branch ${KERNEL_TAG} "${KERNEL_SOURCE}" "${BUILD_DIR}/${SRC_DIR}"
fi
SRC_TAR_DIR="/output/kernel-source"
SRC_TAR_DIR_ORIG="${SRC_TAR_DIR}/original"
SRC_TAR_FILE_ORIG="${SRC_TAR_DIR_ORIG}/${SRC_TARFILE}"
echo "Compressing original sources to ${SRC_TAR_FILE_ORIG}"
mkdir -p $(dirname "${SRC_TAR_FILE_ORIG}")
tar cf - ${SRC_DIR} | xz -T0 -9 > "${SRC_TAR_FILE_ORIG}"


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
else
  echo "No config provided at ${CONFIG_SRC}, building defconfig"
  make $KMAKE_OPTS defconfig
fi

# Do not stop the build on warnings
# This is a problem with the x86_64 defconfig, and not arm64
scripts/config -d CONFIG_WERROR

echo "Checking for certificates..."
# configure for certificates as provided
while IFS=' ' read -r config_setting cert_file; do
  if [ -f "/input/keys/${cert_file}" ]; then
    echo "Certs found at /input/keys/${cert_file} for ${config_setting} - adding to build"
    mkdir -p "${BUILD_DIR}/${SRC_DIR}/keys"
    cp -v "/input/keys/${cert_file}" "${BUILD_DIR}/${SRC_DIR}/keys/"
    scripts/config --set_str "${config_setting}" "keys/${cert_file}"
  else
    echo "Certs not found at /input/keys/${cert_file} - disabling ${config_setting}"
    scripts/config -d ${config_setting}
  fi
done <<< "CONFIG_SYSTEM_TRUSTED_KEYS    trusted-certs.pem
          CONFIG_SYSTEM_REVOCATION_KEYS revocation-certs.pem"

echo "Running olddefconfig..."
make $KMAKE_OPTS olddefconfig

# Create tar file from modified sources with parallel xz compression
echo -e "\n=== Step 5: Creating source tar file with parallel xz compression ==="
cd "$BUILD_DIR"
SRC_TAR_DIR_MOD="${SRC_TAR_DIR}/modified"
SRC_TAR_FILE_MOD="${SRC_TAR_DIR_MOD}/${SRC_TARFILE}"
echo "Compressing modified sources to ${SRC_TAR_FILE_MOD}"
mkdir -p $(dirname "${SRC_TAR_FILE_MOD}")
tar cf - ${SRC_DIR} | xz -T0 -9 > "${SRC_TAR_FILE_MOD}"
cd "${BUILD_DIR}/${SRC_DIR}"

# Build kernel
echo -e "\n=== Step 6: Building kernel and deb packages ==="
echo "Building kernel packages with options ${KMAKE_OPTS}"
time make $KMAKE_OPTS bindeb-pkg

# Build tools
echo -e "\n=== Step 7: Build linux-tools ==="
kuname=$(ar p "${BUILD_DIR}/${SRC_PARENT_DIR}/linux-headers"*.deb control.tar.zst | tar x --zstd -O | grep 'Package' | awk '{print $2}' | sed 's/linux-headers-//g' | sed 's/_.*//g')
kpkg_version=$(ar p "${BUILD_DIR}/${SRC_PARENT_DIR}/linux-headers"*.deb control.tar.zst | tar x --zstd -O | grep 'Version' | awk '{print $2}')
TOOLS_DIR="${BUILD_DIR}/${SRC_PARENT_DIR}/linux-tools-${kuname}"
INST_DIR="${TOOLS_DIR}/usr/lib/linux-tools-cw/${kuname}"
mkdir -p "${INST_DIR}"

pushd "${BUILD_DIR}/${SRC_DIR}/tools/perf"
make $KMAKE_OPTS NO_LIBBPF=1
cp perf "${INST_DIR}/"
popd

pushd "${BUILD_DIR}/${SRC_DIR}/tools/bpf/bpftool"
make $KMAKE_OPTS
cp bpftool "${INST_DIR}/"
popd

mkdir -p "${TOOLS_DIR}/DEBIAN"
cat > "${TOOLS_DIR}/DEBIAN/control" <<EOF
Package: linux-tools-${kuname}
Version: ${kpkg_version}
Architecture: ${ARCH}
Maintainer: Havock <systems-engineering@coreweave.com>
Provides: linux-tools-generic
Depends: libtraceevent1 (>=1:1.3.3-1), libllvm14 (>= 1:14.0.0-1ubuntu1.1)
Description: A minimial debian package that delivers
  the specific binaries of the linux-tools package
  that Coreweave wants to distribute.
EOF

cat > ${TOOLS_DIR}/DEBIAN/postinst <<EOF
#!/bin/sh

path="/usr/lib/linux-tools-cw/$kuname"
install_path="/usr/bin"

if [ -f \$install_path/perf ] || [ -f \$install_path/bpftool ]; then
    rm -rf \$install_path/perf
    rm -rf \$install_path/bpftool
fi

ln -s \$path/perf \$install_path/perf
ln -s \$path/bpftool \$install_path/bpftool
EOF

chmod 0755 ${TOOLS_DIR}/DEBIAN/postinst
dpkg-deb --root-owner-group --build ${TOOLS_DIR}/

# Move build artifacts
echo -e "\n=== Step 8: Moving build artifacts ==="
echo "Moving build artifacts to output directory..."
ls -al "${BUILD_DIR}/${SRC_PARENT_DIR}"
mv -v "${BUILD_DIR}/${SRC_PARENT_DIR}"/*.deb /output/
mv -v "${BUILD_DIR}/${SRC_PARENT_DIR}"/*.buildinfo /output/
mv -v "${BUILD_DIR}/${SRC_PARENT_DIR}"/*.changes /output/

echo -e "\n=== Build complete ==="
echo "Output files are in the output directory."
