fetch_core() {
    # Skip libretro-fetch.sh: libretro-super's recipe points at flyinghead/flycast
    # (CMake-only upstream, 20+ submodules, no PSC-tuned Makefile target). Clone the
    # libretro/flycast mirror instead; it ships a Makefile with a PSC target.
    FLYCAST_DIR="/build/libretro-super/libretro-flycast"
    rm -rf "$FLYCAST_DIR"
    git clone --depth=1 --recurse-submodules --shallow-submodules \
        https://github.com/libretro/flycast.git "$FLYCAST_DIR"

    {
        echo ''
        echo 'INCFLAGS += -isystem /opt/zlib-headers'
        echo 'LIBS += -L/usr/lib/arm-linux-gnueabihf -lz'
    } >> "$FLYCAST_DIR/Makefile"
}

build_core() {
    # ARCH=arm selects gcc, not host `as`, for ngen_arm.S.
    make -C "$FLYCAST_DIR" platform=classic_armv8_a35 ARCH=arm -j"$JOBS" || true
    SO_FILE="$FLYCAST_DIR/flycast_libretro.so"
    if [ -f "$SO_FILE" ]; then
        cp "$SO_FILE" /build/output/
    fi
}

core_source_dir() {
    echo "$FLYCAST_DIR"
}
