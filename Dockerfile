FROM ubuntu:noble

# Set non-interactive mode for apt
ENV DEBIAN_FRONTEND=noninteractive

# Install minimal build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    fakeroot \
    git \
    wget \
    curl \
    debhelper-compat \
    && rm -rf /var/lib/apt/lists/*

# Install cross-compilation toolchains
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc-aarch64-linux-gnu \
    g++-aarch64-linux-gnu \
    && rm -rf /var/lib/apt/lists/*

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
    rsync \
    zstd \
    && rm -rf /var/lib/apt/lists/*

# Set up build environment
ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Create a non-root user for building
RUN useradd -m -s /bin/bash builder

# Create input and output directories
RUN mkdir -p /input /output && \
    chown -R builder:builder /input /output

# Add build script and set permissions
COPY --chown=builder:builder build-kernel.sh /home/builder/
RUN chmod +x /home/builder/build-kernel.sh

# Switch to builder user
USER builder
WORKDIR /home/builder

ENTRYPOINT ["/home/builder/build-kernel.sh"]
