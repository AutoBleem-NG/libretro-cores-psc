patch_core() {
    EMUSCV_MK="/build/libretro-super/libretro-emuscv/Makefile.libretro"
    if [ -f "$EMUSCV_MK" ]; then
        sed -i \
            -e 's|^\t\$(CC) \$(OBJOUT) tools/bin2c/bin2c|\t/usr/bin/gcc $(OBJOUT) tools/bin2c/bin2c|' \
            -e 's|^\t\$(CXX) \$(OBJOUT) tools/dasm7801/dasm7801|\t/usr/bin/g++ $(OBJOUT) tools/dasm7801/dasm7801|' \
            -e 's|^\t@clear|\t@:|' \
            -e 's|^binary\.%\.c: %$|binary.%.c: % tools/bin2c/bin2c$(EXE_EXT)|' \
            "$EMUSCV_MK"
    fi
}

configure_core_flags() {
    # emuscv.h includes <SDL2/SDL.h>, while its Makefile only adds
    # -I/usr/include/SDL2. Search host /usr/include after the cross sysroot.
    export CFLAGS="$CFLAGS -idirafter /usr/include"
    export CXXFLAGS="$CXXFLAGS -idirafter /usr/include"

    # Generated binary*.h files lack proper dependencies for parallel builds.
    export JOBS=1
}
