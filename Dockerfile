FROM ubuntu:noble

# Set non-interactive mode for apt
ENV DEBIAN_FRONTEND=noninteractive

# Annotate apt sources to be amd64 specific
# This is needed to properly handle arm64 repos
RUN sed -i 's/^\(URIs:.*\)$/\1\nArchitectures: amd64/' /etc/apt/sources.list.d/ubuntu.sources

COPY ubuntu-arm64.sources /etc/apt/sources.list.d/

RUN dpkg --add-architecture arm64

# Install script helpers
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    yq \
    && rm -rf /var/lib/apt/lists/*

# Install minimal build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    debhelper-compat \
    fakeroot \
    g++-12 \
    gcc-12 \
    g++-13 \
    gcc-13 \
    git \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install cross-compilation toolchains
RUN apt-get update && apt-get install -y --no-install-recommends \
    g++-13-aarch64-linux-gnu \
    gcc-13-aarch64-linux-gnu \
    g++-12-aarch64-linux-gnu \
    gcc-12-aarch64-linux-gnu \
    && rm -rf /var/lib/apt/lists/*

# RUN apt-get update && apt-get install -y --no-install-recommends \
#     g++-aarch64-linux-gnu \
#     gcc-aarch64-linux-gnu \
#     g++-13-aarch64-linux-gnu \
#     gcc-13-aarch64-linux-gnu \
#     g++-12-aarch64-linux-gnu \
#     gcc-12-aarch64-linux-gnu \
#     && rm -rf /var/lib/apt/lists/*

# Install kernel build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    bc \
    bison \
    cpio \
    dwarves \
    flex \
    gawk \
    kmod \
    libdw-dev \
    libelf-dev \
    libncurses-dev \
    libssl-dev \
    libudev-dev \
    openssl \
    pkg-config \
    python3 \
    python3-dev \
    python3-setuptools \
    rsync \
    zstd \
    && rm -rf /var/lib/apt/lists/*

# Install amd64 build dependencies for userspace tools
# RUN apt-get update && apt-get install -y --no-install-recommends \
#     libbabeltrace-dev \
#     libcap-dev \
#     libnuma-dev \
#     libpci-dev \
#     libperl-dev \
#     libpfm4-dev \
#     libslang2-dev \
#     libtraceevent-dev \
#     libunwind-dev \
#     systemtap-sdt-dev \
#     && rm -rf /var/lib/apt/lists/*

# Install arm64 build dependencies for userspace tools
# To install the python3-dev package, which execs the arm64 python interpreter
# you must do the following for your contain build environment:
# * apt-get install -y binfmt-support qemu-user-static
# * docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
# RUN apt-get update && apt-get install -y --no-install-recommends \
#     libbabeltrace-dev:arm64 \
#     libbpf-dev:arm64 \
#     libbpfcc-dev:arm64 \
#     libcap-dev:arm64 \
#     libdw-dev:arm64 \
#     libelf-dev:arm64 \
#     libnuma-dev:arm64 \
#     libpci-dev:arm64 \
#     libperl-dev:arm64 \
#     libpfm4-dev:arm64 \
#     libslang2-dev:arm64 \
#     libssl-dev:arm64 \
#     libtraceevent-dev:arm64 \
#     libunwind-dev:arm64 \
#     pkg-config:arm64 \
#     python3-dev:arm64 \
#     python3-setuptools:arm64 \
#     systemtap-sdt-dev:arm64 \
#     && rm -rf /var/lib/apt/lists/*

# RUN apt-get update && apt-get install -y --no-install-recommends \
#     clang-17 \
#     libpci-dev \
#     llvm-17-dev \
#     && rm -rf /var/lib/apt/lists/*

# Update alternatives
RUN for app in cpp g++ gcc gcc-ar gcc-nm gcc-ranlib gcov gcov-dump gcov-tool lto-dump; do \
      for arch in aarch64 x86_64; do \
        for ver in 12 13; do \
          update-alternatives --install /usr/bin/${arch}-linux-gnu-${app} ${app}-${arch} /usr/bin/${arch}-linux-gnu-${app}-${ver} ${ver}; \
        done; \
        update-alternatives --set ${app}-${arch} /usr/bin/${arch}-linux-gnu-${app}-13; \
      done; \
    done

# Set up build environment
ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Create a non-root user for building
RUN useradd -m -s /bin/bash builder

# Add builder to sudoers for apt access
COPY builder.sudo /etc/sudoers.d/builder

# Create input and output directories
RUN mkdir -p /input /output && \
    chown -R builder:builder /input /output

# Add build script and set permissions
COPY --chown=builder:builder log-build-to-output.sh build-kernel.sh /home/builder/
RUN chmod +x /home/builder/log-build-to-output.sh /home/builder/build-kernel.sh

# Switch to builder user
USER builder
WORKDIR /home/builder

ENTRYPOINT ["/home/builder/log-build-to-output.sh"]
