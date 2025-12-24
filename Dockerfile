# Libretro Cores PSC - Self-contained Cross-compilation for PlayStation Classic
# Builds crosstool-ng toolchain from scratch, no external dependencies
#
# Build: make image
# Usage: make (all cores) or make CORE=snes9x (single core)

# ==============================================================================
# Version Configuration
# ==============================================================================
ARG CROSSTOOL_NG_VERSION=1.28.0

# libretro-super commit (update periodically for new cores/fixes)
# Check latest: git ls-remote https://github.com/libretro/libretro-super.git HEAD
ARG LIBRETRO_SUPER_REF=6244066badefb5ccca99e621ce0e653748bb8f37

# Toolchain versions - matched for PlayStation Classic compatibility
ARG CT_LINUX_VERSION=4_4
ARG CT_BINUTILS_VERSION=2_32
ARG CT_GLIBC_VERSION=2_23
ARG CT_GCC_VERSION=9

# User IDs for crosstool-ng build
ARG CTNG_UID=1000
ARG CTNG_GID=1000

# ==============================================================================
# Stage 1: Build Custom GCC Toolchain with crosstool-ng
# ==============================================================================
FROM ubuntu:16.04 AS ctngbuild

ARG CTNG_UID
ARG CTNG_GID
ARG CROSSTOOL_NG_VERSION
ARG CT_LINUX_VERSION
ARG CT_BINUTILS_VERSION
ARG CT_GLIBC_VERSION
ARG CT_GCC_VERSION

# Create user for crosstool-ng (cannot run as root)
RUN groupadd -g $CTNG_GID ctng && \
    useradd -d /home/ctng -m -g $CTNG_GID -u $CTNG_UID -s /bin/bash ctng

# Install crosstool-ng build dependencies
RUN apt-get update && \
    apt-get install -y \
        gcc g++ gperf bison flex texinfo help2man make libncurses5-dev \
        python3-dev autoconf automake libtool libtool-bin gawk wget bzip2 \
        xz-utils unzip patch libstdc++6 rsync meson ninja-build && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Setup crosstool-ng directories
RUN mkdir /opt/ctng && chmod 777 /opt/ctng && \
    mkdir /opt/x-tools && chmod 777 /opt/x-tools && \
    echo 'export PATH=/opt/ctng/bin:$PATH' >> /etc/profile

USER ctng

# Download and build crosstool-ng
RUN wget -O /tmp/crosstool.bz2 http://crosstool-ng.org/download/crosstool-ng/crosstool-ng-${CROSSTOOL_NG_VERSION}.tar.bz2 && \
    cd /home/ctng && tar xvf /tmp/crosstool.bz2 && \
    rm /tmp/crosstool.bz2 && \
    cd /home/ctng/crosstool-ng-${CROSSTOOL_NG_VERSION} && \
    ./configure --prefix=/opt/ctng && \
    make && \
    make install

# Configure and build ARM toolchain for PlayStation Classic
RUN echo 'CT_CONFIG_VERSION="4"' >> /tmp/defconfig && \
    echo 'CT_PREFIX_DIR="/opt/x-tools/${CT_HOST:+HOST-${CT_HOST}/}${CT_TARGET}"' >> /tmp/defconfig && \
    echo 'CT_ARCH_ARM=y' >> /tmp/defconfig && \
    echo 'CT_OMIT_TARGET_VENDOR=y' >> /tmp/defconfig && \
    echo 'CT_ARCH_FLOAT_HW=y' >> /tmp/defconfig && \
    echo 'CT_KERNEL_LINUX=y' >> /tmp/defconfig && \
    echo 'CT_LINUX_V_'${CT_LINUX_VERSION}'=y' >> /tmp/defconfig && \
    echo 'CT_BINUTILS_V_'${CT_BINUTILS_VERSION}'=y' >> /tmp/defconfig && \
    echo 'CT_GLIBC_V_'${CT_GLIBC_VERSION}'=y' >> /tmp/defconfig && \
    echo 'CT_GCC_V_'${CT_GCC_VERSION}'=y' >> /tmp/defconfig && \
    echo 'CT_CC_LANG_CXX=y' >> /tmp/defconfig && \
    echo 'CT_CC_GCC_LIBGOMP=y' >> /tmp/defconfig && \
    cd /tmp && /opt/ctng/bin/ct-ng defconfig && \
    echo 'CT_ZLIB_MIRRORS="http://downloads.sourceforge.net/project/libpng/zlib/${CT_ZLIB_VERSION} https://www.zlib.net/ https://www.zlib.net/fossils"' >> /tmp/.config && \
    cd /tmp && /opt/ctng/bin/ct-ng build

# ==============================================================================
# Stage 2: Libretro Core Build Environment
# ==============================================================================
FROM ubuntu:18.04

ARG LIBRETRO_SUPER_REF

LABEL maintainer="AutoBleem-NG"
LABEL description="Docker build environment for Libretro cores - PlayStation Classic"

ENV DEBIAN_FRONTEND=noninteractive

# ==============================================================================
# Install Build Dependencies
# ==============================================================================
RUN apt-get update && apt-get install -y \
    git \
    make \
    cmake \
    autoconf \
    pkg-config \
    pkg-config-arm-linux-gnueabihf \
    wget \
    curl \
    xz-utils \
    patchelf \
    bsdmainutils \
    mesa-common-dev \
    libgl1-mesa-dev \
    && rm -rf /var/lib/apt/lists/*

# ==============================================================================
# Install ARM Libraries
# ==============================================================================
RUN dpkg --add-architecture armhf && \
    mv /etc/apt/sources.list /etc/apt/sources.list.bak && \
    echo "deb [arch=amd64] http://archive.ubuntu.com/ubuntu bionic main universe" > /etc/apt/sources.list && \
    echo "deb [arch=amd64] http://archive.ubuntu.com/ubuntu bionic-updates main universe" >> /etc/apt/sources.list && \
    echo "deb [arch=armhf] http://ports.ubuntu.com/ubuntu-ports bionic main universe" >> /etc/apt/sources.list && \
    echo "deb [arch=armhf] http://ports.ubuntu.com/ubuntu-ports bionic-updates main universe" >> /etc/apt/sources.list && \
    apt-get update && apt-get install -y \
    libasound2-dev:armhf \
    libudev-dev:armhf \
    libusb-1.0-0-dev:armhf \
    libsdl2-dev:armhf \
    libsdl2-dev \
    libgles2-mesa-dev:armhf \
    libegl1-mesa-dev:armhf \
    libdrm-dev:armhf \
    libgbm-dev:armhf \
    libfreetype6-dev:armhf \
    libfreetype6-dev \
    libwayland-dev:armhf \
    libxkbcommon-dev:armhf \
    libexpat1-dev:armhf \
    zlib1g-dev:armhf \
    libpng-dev:armhf \
    libgl1-mesa-dev:armhf \
    && apt-get remove -y libpulse-dev:armhf || true \
    && rm -rf /var/lib/apt/lists/*

# ==============================================================================
# Copy Custom Toolchain from Stage 1
# ==============================================================================
RUN mkdir -p /opt/x-tools
COPY --from=ctngbuild /opt/x-tools/arm-linux-gnueabihf /opt/x-tools/arm-linux-gnueabihf

# ==============================================================================
# Environment Setup for Cross-Compilation
# ==============================================================================
ENV PATH="/opt/x-tools/arm-linux-gnueabihf/bin:${PATH}"
ENV CC=arm-linux-gnueabihf-gcc
ENV CXX=arm-linux-gnueabihf-g++
ENV AR=arm-linux-gnueabihf-ar
ENV PKG_CONFIG_PATH=/usr/lib/arm-linux-gnueabihf/pkgconfig
ENV PKG_CONFIG_LIBDIR=/usr/lib/arm-linux-gnueabihf/pkgconfig
ENV PKG_CONFIG=/usr/bin/arm-linux-gnueabihf-pkg-config
ENV LDFLAGS="-L/usr/lib/arm-linux-gnueabihf -Wl,-rpath-link,/usr/lib/arm-linux-gnueabihf"
ENV LIBRARY_PATH=/usr/lib/arm-linux-gnueabihf

# Create dummy immintrin.h for ARM cross-compilation
RUN mkdir -p /opt/arm-compat-headers && \
    echo '/* Dummy immintrin.h for ARM cross-compilation */' > /opt/arm-compat-headers/immintrin.h

# Create wrapper scripts for crosstool-ng compiler with proper include paths
RUN echo '#!/bin/bash' > /usr/bin/psc-gcc && \
    echo 'exec /opt/x-tools/arm-linux-gnueabihf/bin/arm-linux-gnueabihf-gcc -I/opt/arm-compat-headers -I/usr/include/SDL2 -idirafter /usr/include -idirafter /usr/include/arm-linux-gnueabihf -L/usr/lib/arm-linux-gnueabihf "$@"' >> /usr/bin/psc-gcc && \
    chmod +x /usr/bin/psc-gcc && \
    echo '#!/bin/bash' > /usr/bin/psc-g++ && \
    echo 'exec /opt/x-tools/arm-linux-gnueabihf/bin/arm-linux-gnueabihf-g++ -I/opt/arm-compat-headers -I/usr/include/SDL2 -idirafter /usr/include -idirafter /usr/include/arm-linux-gnueabihf -L/usr/lib/arm-linux-gnueabihf "$@"' >> /usr/bin/psc-g++ && \
    chmod +x /usr/bin/psc-g++

# Fix ARM library symlinks
RUN ln -sf libSDL2-2.0.so.0 /usr/lib/arm-linux-gnueabihf/libSDL2.so && \
    ln -sf libEGL.so.1 /usr/lib/arm-linux-gnueabihf/libEGL.so && \
    ln -sf libGLESv2.so.2 /usr/lib/arm-linux-gnueabihf/libGLESv2.so && \
    ln -sf libdrm.so.2 /usr/lib/arm-linux-gnueabihf/libdrm.so && \
    ln -sf libgbm.so.1 /usr/lib/arm-linux-gnueabihf/libgbm.so

# ==============================================================================
# Libretro Core Build Setup
# ==============================================================================
WORKDIR /build

# Download zlib headers and copy GL/GLES/EGL/KHR headers (avoid glibc conflicts)
# PSC has Mali-T720 GPU with OpenGL ES 3.1 support
RUN mkdir -p /opt/zlib-headers/GL /opt/zlib-headers/GLES2 /opt/zlib-headers/GLES3 \
             /opt/zlib-headers/EGL /opt/zlib-headers/KHR && \
    wget -q https://zlib.net/fossils/zlib-1.2.11.tar.gz -O /tmp/zlib.tar.gz && \
    tar -xzf /tmp/zlib.tar.gz -C /tmp && \
    cp /tmp/zlib-1.2.11/zlib.h /tmp/zlib-1.2.11/zconf.h /opt/zlib-headers/ && \
    rm -rf /tmp/zlib* && \
    cp /usr/include/png*.h /opt/zlib-headers/ 2>/dev/null || true && \
    cp /usr/include/GL/*.h /opt/zlib-headers/GL/ 2>/dev/null || true && \
    cp /usr/include/GLES2/*.h /opt/zlib-headers/GLES2/ 2>/dev/null || true && \
    cp /usr/include/GLES3/*.h /opt/zlib-headers/GLES3/ 2>/dev/null || true && \
    cp /usr/include/EGL/*.h /opt/zlib-headers/EGL/ 2>/dev/null || true && \
    cp /usr/include/KHR/*.h /opt/zlib-headers/KHR/ 2>/dev/null || true

# Clone libretro-super for core fetching/building (pinned version)
RUN git clone https://github.com/libretro/libretro-super.git && \
    cd libretro-super && \
    git checkout ${LIBRETRO_SUPER_REF}

# PSC-optimized compiler flags (Cortex-A35)
# Note: -isystem makes zlib-headers a "system include" searched AFTER local includes
# This allows cores with bundled zlib to use their own headers first
ENV PSC_CFLAGS="-march=armv8-a -mtune=cortex-a35 -mfpu=neon-fp-armv8 -mfloat-abi=hard -O3 -funroll-loops -ftree-vectorize -ffunction-sections -fdata-sections -isystem /opt/zlib-headers"
ENV PSC_LDFLAGS="-Wl,--gc-sections -Wl,--as-needed -L/usr/lib/arm-linux-gnueabihf -lz"

# libretro-super platform setting
# NOTE: "armv7" selects 32-bit ARM build rules (PSC has 32-bit userspace)
# Actual ARMv8 instruction set comes from PSC_CFLAGS (-march=armv8-a)
ENV platform="linux-armv7-neon-hardfloat"
ENV JOBS="4"

# Create output directory
RUN mkdir -p /build/output

# Copy build scripts
COPY build-core.sh /build/
RUN chmod +x /build/build-core.sh

# Default: interactive shell
CMD ["/bin/bash"]
