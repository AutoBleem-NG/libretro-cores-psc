#!/bin/bash
# Build a single libretro core for PSC.
set -e

CORE_NAME="${1:-}"
if [ -z "$CORE_NAME" ]; then
    echo "Usage: $0 <core_name>"
    echo "Example: $0 snes9x"
    exit 1
fi

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
CORE_FIXES_DIR="${CORE_FIXES_DIR:-$SCRIPT_DIR/core-fixes}"

# Use JOBS from environment or default to 4.
export JOBS="${JOBS:-4}"

cd /build/libretro-super

SO_OUT="/build/output/${CORE_NAME}_libretro.so"
METADATA_OUT="${BUILD_METADATA_DIR:-/build/metadata}"
if [ ! -d "$METADATA_OUT" ]; then
    METADATA_OUT="/build/output/.metadata"
fi
COMMIT_OUT="${METADATA_OUT}/commits/${CORE_NAME}_libretro.so.commit"
mkdir -p "$METADATA_OUT"
mkdir -p "$(dirname "$COMMIT_OUT")"
rm -f "$SO_OUT" "$COMMIT_OUT" "${SO_OUT}.commit"

fetch_core() {
    ./libretro-fetch.sh "$CORE_NAME"

    # Initialize submodules recursively (fixes tic80, scummvm, etc.).
    CORE_DIR=$(find libretro-* -maxdepth 0 -type d -name "*${CORE_NAME}*" 2>/dev/null | head -1)
    if [ -d "$CORE_DIR" ]; then
        echo "=== Initializing submodules in $CORE_DIR ==="
        cd "$CORE_DIR"
        git submodule update --init --recursive 2>/dev/null || true
        cd /build/libretro-super
    fi
}

patch_core() {
    :
}

configure_core_flags() {
    :
}

build_core() {
    ./libretro-build.sh "$CORE_NAME" || true

    # Fix case-mismatched output filenames (e.g. FreeIntv_libretro.so -> freeintv_libretro.so).
    EXPECTED_FILE="dist/unix/${CORE_NAME}_libretro.so"
    if [ ! -f "$EXPECTED_FILE" ]; then
        ACTUAL_FILE=$(find dist/unix -maxdepth 1 -iname "${CORE_NAME}_libretro.so" 2>/dev/null | head -1)

        if [ -z "$ACTUAL_FILE" ] || [ ! -f "$ACTUAL_FILE" ]; then
            ACTUAL_FILE=$(find libretro-* -name "*_libretro.so" -iname "${CORE_NAME}_libretro.so" 2>/dev/null | head -1)
        fi

        if [ -n "$ACTUAL_FILE" ] && [ -f "$ACTUAL_FILE" ]; then
            echo "=== Fixing filename case: $(basename "$ACTUAL_FILE") -> ${CORE_NAME}_libretro.so ==="
            cp "$ACTUAL_FILE" "$EXPECTED_FILE"
        fi
    fi

    if [ -f "$EXPECTED_FILE" ]; then
        cp "$EXPECTED_FILE" /build/output/
    fi
}

core_source_dir() {
    RESOLVED_DIR=$(
        cd /build/libretro-super 2>/dev/null || exit
        # shellcheck disable=SC1091
        . rules.d/core-rules.sh 2>/dev/null
        eval "echo \${libretro_${CORE_NAME}_dir:-libretro-${CORE_NAME}}"
    )
    echo "/build/libretro-super/$RESOLVED_DIR"
}

if [ -f "$CORE_FIXES_DIR/$CORE_NAME.sh" ]; then
    # shellcheck disable=SC1090
    . "$CORE_FIXES_DIR/$CORE_NAME.sh"
fi

# Fix broken Bitbucket submodule URLs for ecwolf (all three deps moved to github.com/ECWolfEngine).
if [ "$CORE_NAME" = "ecwolf" ]; then
    git config --global url."https://github.com/ECWolfEngine/sdl".insteadOf "https://bitbucket.org/ecwolf/sdl"
    git config --global url."https://github.com/ECWolfEngine/sdl_mixer-for-ecwolf".insteadOf "https://bitbucket.org/ecwolf/sdl_mixer-for-ecwolf"
    git config --global url."https://github.com/ECWolfEngine/sdl_net".insteadOf "https://bitbucket.org/ecwolf/sdl_net"
fi

echo "=== Fetching $CORE_NAME ==="
fetch_core

patch_core

echo "=== Building $CORE_NAME (JOBS=$JOBS) ==="
export CFLAGS="$PSC_CFLAGS"
export CXXFLAGS="$PSC_CFLAGS"
export LDFLAGS="$PSC_LDFLAGS"
configure_core_flags

build_core

echo "=== Copying output ==="

if [ ! -f "$SO_OUT" ]; then
    echo "Error: ${CORE_NAME}_libretro.so was not produced" >&2
    exit 1
fi

echo "=== Stripping binary ==="
arm-linux-gnueabihf-strip -v "$SO_OUT"

SRC_DIR="$(core_source_dir)"
if [ -d "$SRC_DIR/.git" ]; then
    COMMIT=$(cd "$SRC_DIR" && git rev-parse HEAD 2>/dev/null)
    URL=$(cd "$SRC_DIR" && git config --get remote.origin.url 2>/dev/null)
    if [ -n "$COMMIT" ]; then
        echo "=== Recording source commit: $COMMIT ==="
        {
            echo "core=$CORE_NAME"
            echo "commit=$COMMIT"
            echo "url=$URL"
            echo "build_date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        } > "$COMMIT_OUT"
    else
        echo "Warning: could not determine commit for $CORE_NAME (src=$SRC_DIR)" >&2
    fi
else
    echo "Warning: source dir $SRC_DIR missing or not a git repo for $CORE_NAME" >&2
fi

echo "=== Done: $CORE_NAME ==="
ls -lh "$SO_OUT" "$COMMIT_OUT" 2>/dev/null || true
