build_core() {
    SRC_DIR="$(core_source_dir)"
    cd "$SRC_DIR"

    if ! grep -q -- "-DEGL_NO_X11" Makefile; then
        sed -i 's/COREFLAGS += -DOS_LINUX/COREFLAGS += -DOS_LINUX -DEGL_NO_X11/g' Makefile
    fi

    make clean platform=odroid BOARD=ODROIDGOA || true
    make -j"$JOBS" \
        platform=odroid \
        BOARD=ODROIDGOA \
        FORCE_GLES=1 \
        CC=arm-linux-gnueabihf-gcc \
        CXX=arm-linux-gnueabihf-g++ \
        AR=arm-linux-gnueabihf-ar \
        STRIP=arm-linux-gnueabihf-strip

    cp mupen64plus_next_libretro.so /build/output/
}
