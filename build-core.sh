#!/bin/bash
# Build a single libretro core for PSC
set -e

CORE_NAME="${1:-}"
if [ -z "$CORE_NAME" ]; then
    echo "Usage: $0 <core_name>"
    echo "Example: $0 snes9x"
    exit 1
fi

# Use JOBS from environment or default to 4
export JOBS="${JOBS:-4}"

cd /build/libretro-super

echo "=== Fetching $CORE_NAME ==="
./libretro-fetch.sh "$CORE_NAME"

# Initialize submodules recursively (fixes tic80, scummvm, etc.)
CORE_DIR=$(find libretro-* -maxdepth 0 -type d -name "*${CORE_NAME}*" 2>/dev/null | head -1)
if [ -d "$CORE_DIR" ]; then
    echo "=== Initializing submodules in $CORE_DIR ==="
    cd "$CORE_DIR"
    git submodule update --init --recursive 2>/dev/null || true
    cd /build/libretro-super
fi

echo "=== Building $CORE_NAME (JOBS=$JOBS) ==="
export CFLAGS="$PSC_CFLAGS"
export CXXFLAGS="$PSC_CFLAGS"
export LDFLAGS="$PSC_LDFLAGS"

./libretro-build.sh "$CORE_NAME" || true

# Fix case-mismatched output filenames (e.g., FreeIntv_libretro.so -> freeintv_libretro.so)
# Check both dist/unix and core build directories
EXPECTED_FILE="dist/unix/${CORE_NAME}_libretro.so"
if [ ! -f "$EXPECTED_FILE" ]; then
    # Look for case-insensitive match in dist/unix first
    ACTUAL_FILE=$(find dist/unix -maxdepth 1 -iname "${CORE_NAME}_libretro.so" 2>/dev/null | head -1)

    # If not found, search in core build directories
    if [ -z "$ACTUAL_FILE" ] || [ ! -f "$ACTUAL_FILE" ]; then
        ACTUAL_FILE=$(find libretro-* -name "*_libretro.so" -iname "${CORE_NAME}_libretro.so" 2>/dev/null | head -1)
    fi

    if [ -n "$ACTUAL_FILE" ] && [ -f "$ACTUAL_FILE" ]; then
        echo "=== Fixing filename case: $(basename "$ACTUAL_FILE") -> ${CORE_NAME}_libretro.so ==="
        cp "$ACTUAL_FILE" "$EXPECTED_FILE"
    fi
fi

echo "=== Copying output ==="
find dist/unix -name "*.so" -exec cp {} /build/output/ \;

echo "=== Stripping binaries ==="
for so in /build/output/*.so; do
    if [ -f "$so" ]; then
        arm-linux-gnueabihf-strip -v "$so"
    fi
done

echo "=== Done: $CORE_NAME ==="
ls -lh /build/output/
