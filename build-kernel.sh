#!/bin/bash
set -e

# Set architecture and cross-compilation settings
# Default to 64-bit Intel
ARCH=${ARCH:-x86_64}
CROSS_COMPILE=x86_64-linux-gnu-
COMPILER_ARCH=x86_64
PACKAGE_ARCH=amd64

if [ "x${ARCH}" == "xamd64" ]; then
  # Old habits die hard
  ARCH=x86_64
fi

if [ "x${ARCH}" == "xarm64" ]; then
  CROSS_COMPILE=aarch64-linux-gnu-
  COMPILER_ARCH=aarch64
  PACKAGE_ARCH=arm64
fi

# Default to Ubuntu Noble kernel
# KERNEL_TAG: Git kernel tag or branch to checkout.
# KERNELRELEASE: The first part of the kernel and package name
# COMPILER_VERSION: Jammy == 12, Noble == 13
KERNEL_SOURCE=${KERNEL_SOURCE:-git://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/noble}
KERNEL_TAG=${KERNEL_TAG:-Ubuntu-6.8.0-60.63}
KERNELRELEASE=${KERNELRELEASE:-6.8.0-60.63}
COMPILER_VERSION=${COMPILER_VERSION:-13}

# Use gcc-12 for the Ubuntu Jammy release
if [ "x${KERNELRELEASE:0:3}" == "x6.5" ]; then
  COMPILER_VERSION=12
fi

# The default alternatives are for gcc-12. Change them for other compiler versions
# The alternatives should be set up in the Dockerfile
if [ "x${COMPILER_VERSION}" != "x13" ]; then
  for app in cpp g++ gcc gcc-ar gcc-nm gcc-ranlib gcov gcov-dump gcov-tool lto-dump; do
    sudo update-alternatives --set ${app}-${COMPILER_ARCH} /usr/bin/${CROSS_COMPILE}${app}-${COMPILER_VERSION}
  done
fi

KMAKE_OPTS="ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE KERNELRELEASE=${KERNELRELEASE} -j$(nproc)"

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
SRC_TARFILE="${SRC_TARFILE:-${KERNEL_TAG}-src.tar.xz}"

# Set up the kernel build directory, deleting anything previously used
echo "=== Step 1: Creating kernel build directory ==="
# Create build directory
if [ -d "$BUILD_DIR" ]; then
  echo "Old build directory found. Deleting"
  rm -rf "$BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Get kernel source
# If a file in the input directory is found, use it instead of the long
# `git clone` process
echo -e "\n=== Step 2: Preparing kernel source ==="
if [ -f "/input/${SRC_TARFILE}" ]; then
  echo "Using provided kernel source archive in tar file ${SRC_TARFILE}"
  tar xf "/input/${SRC_TARFILE}"
else
  echo "Source code archive not found at ${SRC_TARFILE}"
  echo "Cloning kernel source from Ubuntu repository (version: $KERNEL_TAG)"
  git -c http.sslVerify=false clone --depth 1 --branch ${KERNEL_TAG} "${KERNEL_SOURCE}" "${BUILD_DIR}/${SRC_DIR}"
fi

# Create a clean image of the source directory for reuse purposes. This file
# will have the same name needed to be used in the input directory
# This is a slow process, and can be eliminated by setting SRC_BACKUP_DIR to "none"
SRC_BACKUP_DIR=${SRC_BACKUP_DIR:-"/output/kernel-source"}
if [ "x${SRC_BACKUP_DIR}" != "xnone" ]; then
  SRC_BACKUP_DIR_ORIG="${SRC_BACKUP_DIR}/original"
  SRC_BACKUP_TARFILE_ORIG="${SRC_BACKUP_DIR_ORIG}/${SRC_TARFILE}"
  echo "Compressing original sources to ${SRC_BACKUP_TARFILE_ORIG}"
  mkdir -p $(dirname "${SRC_BACKUP_TARFILE_ORIG}")
  tar cf - ${SRC_DIR} | xz -T0 -9 > "${SRC_BACKUP_TARFILE_ORIG}"
else
  echo "No source backup explicitly requested. Original source not backed up"
fi

cd "${BUILD_DIR}/${SRC_DIR}"

# Patches should be placed in a directory "patches" in the input directory
# There is an arch-specific directory and an "all" directory that will be
# searched in the "patches" directory.
# Any filename that starts with a period will be treated as hidden and skipped
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

# Configure kernel. Config file can be provided with CONFIG_SRC var
# or by placing a file in the input directory named "config-<git tag>-<arch>"
# If no config file can be found, the "defconfig" build is performed. Use at
# your own risk.
echo -e "\n=== Step 4: Configuring kernel ==="
CONFIG_SRC="${CONFIG_SRC:-/input/config-${KERNEL_TAG}-${ARCH}}"
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
# Certificates can be stored in the "keys" directory of the input directory.
# Two files are searched for: trusted-certs.pem and revocation-certs.pem
# This script creates a "keys" directory in the kernel source and copies these
# two files if they exist.
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

# Final cleaning build of the config file. Just in case the user-provided config
# has problems
echo "Running olddefconfig..."
make $KMAKE_OPTS olddefconfig

# Create tar file from modified sources with parallel xz compression
# Preserves the config file and patches made to the source. This can be used
# for crash debugging sessions.
# WARNING: Also preserves private keys. Publish at your own risk.
# Again, this is a slow process and can be short-circuited by setting
# SRC_BACKUP_DIR to "none"
if [ "x${SRC_BACKUP_DIR}" != "xnone" ]; then
  pushd "$BUILD_DIR"
  SRC_BACKUP_DIR_MOD="${SRC_BACKUP_DIR}/modified"
  SRC_BACKUP_TARFILE_MOD="${SRC_BACKUP_DIR_MOD}/${SRC_TARFILE}"
  echo "Compressing modified sources to ${SRC_BACKUP_TARFILE_MOD}"
  mkdir -p $(dirname "${SRC_BACKUP_TARFILE_MOD}")
  tar cf - ${SRC_DIR} | xz -T0 -9 > "${SRC_BACKUP_TARFILE_MOD}"
  popd
else
  echo "No source backup explicitly requested. Modified source not backed up"
fi

# Build kernel. Rubber->Road. Crap->Fan.
echo -e "\n=== Step 6: Building kernel and deb packages ==="
echo "Building kernel packages with options ${KMAKE_OPTS}"
time make $KMAKE_OPTS bindeb-pkg

# Build tools
# This relies on a file "tools.yaml" in the input directory. The base list of
# the YAML file are dictionary elements that describe each tool to build. The
# attributes for each directory element are:
# - name: (required) Name of the tool binary that will be built
#         TODO: handle tool builds with multiple binaries
# - enabled: (required) true or false - build it or skip it. Allows for tool
#            definitions to exist but not build if not needed
# - path: (required) Path to the build directory under the kernel source tools
#         directory
# - build_options: (optional) Options to add to the kernel make command beyond
#                  those used for the kernel build
# - packages: (optional) Installable packages needed by the tool build. These
#             package lists will be glommed together and installed before
#             any tool is built. The --no-install-recommends flag is used
#             during the install, so be explicit with all required dependencies
echo -e "\n=== Step 7: Build linux-tools ==="
if [ ! -f /input/tools.yaml ]; then
  echo "File tools.yaml not found in input directory. Skipping tools build"
elif [ "x$(yq -r '.[] | select(.enabled).name' /input/tools.yaml)" == "x" ]; then
  echo "No enabled tools to build found in tools.yaml"
else
  # Pull the final kernel uname and package version from kernel packages
  kuname=$(ar p "${BUILD_DIR}/${SRC_PARENT_DIR}/linux-headers"*.deb control.tar.zst | tar x --zstd -O | grep 'Package' | awk '{print $2}' | sed 's/linux-headers-//g' | sed 's/_.*//g')
  kpkg_version=$(ar p "${BUILD_DIR}/${SRC_PARENT_DIR}/linux-headers"*.deb control.tar.zst | tar x --zstd -O | grep 'Version' | awk '{print $2}')
  # Paths to the final packaging build directories
  TOOLS_DIR="${BUILD_DIR}/${SRC_PARENT_DIR}/linux-tools-${kuname}"
  INST_DIR="${TOOLS_DIR}/usr/lib/linux-tools-cw/${kuname}"
  mkdir -p "${INST_DIR}"

  # Install dependent packages
  sudo apt update && sudo apt install -y --no-install-recommends yq $(yq -r ".[] | select(.enabled and .packages).packages | map(. + \":${PACKAGE_ARCH}\") | flatten | join (\" \")" /input/tools.yaml)

  # Build each enabled tool
  yq -r '.[] | select(.enabled).name' /input/tools.yaml | while read toolname; do
    TOOL_PATH=$(yq -r ".[] | select(.name == \"${toolname}\").path" /input/tools.yaml)
    echo "Building tool ${toolname} in path ${TOOL_PATH}"
    pushd "${BUILD_DIR}/${SRC_DIR}/tools/${TOOL_PATH}"
    TOOL_BUILD_OPTS=$(yq -r ".[] | select(.name == \"${toolname}\" and .build_options).build_options | join(\" \")" /input/tools.yaml)
    make $KMAKE_OPTS $TOOL_BUILD_OPTS
    cp -v "${toolname}" "${INST_DIR}/"
    popd
  done

  # Debian control file for tools package
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

  # Post-install script, to link tools files into the /usr/bin directory
  cat > ${TOOLS_DIR}/DEBIAN/postinst <<EOF
#!/bin/sh

path="/usr/lib/linux-tools-cw/$kuname"
install_path="/usr/bin"

ln -sf \$path/* \$install_path/
EOF

  chmod 0755 ${TOOLS_DIR}/DEBIAN/postinst
  dpkg-deb --root-owner-group --build ${TOOLS_DIR}/
fi

# Move build artifacts to the output directory
echo -e "\n=== Step 8: Moving build artifacts ==="
echo "Moving build artifacts to output directory..."
ls -al "${BUILD_DIR}/${SRC_PARENT_DIR}"
mv -v "${BUILD_DIR}/${SRC_PARENT_DIR}"/*.deb /output/
mv -v "${BUILD_DIR}/${SRC_PARENT_DIR}"/*.buildinfo /output/
mv -v "${BUILD_DIR}/${SRC_PARENT_DIR}"/*.changes /output/

echo -e "\n=== Build complete ==="
echo "Output files are in the output directory."
