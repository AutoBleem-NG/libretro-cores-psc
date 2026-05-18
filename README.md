# libretro-cores-psc

Cross-compiled libretro emulator cores optimized for PlayStation Classic.

## Requirements

- Docker
- Make

## Usage

```bash
make                     # Build all cores (parallel)
make CORE=snes9x         # Build single core
make PARALLEL=16         # Adjust parallelism
make status              # Show build progress
make core-info           # Generate dist/info metadata for enabled cores
make audit-cores         # Compare cores.txt with pinned libretro-super rules
make retry-failed        # Retry unresolved failures from the last full build
make release             # Create release archive
make help                # Show all commands
```

Outputs:

- `build_metadata/COMMITS.txt` - source commit manifest for built cores
- `build_metadata/VERSION` - build/toolchain version info
- `build_metadata/commits/*.so.commit` - per-core commit sidecars used to build the manifest
- `build_status/{success,failed,skipped}.txt` - latest build run status
- `dist/cores/*.so` - built libretro cores
- `dist/info/*.info` - libretro core metadata copied from the pinned `libretro-super` checkout

## Cores

Edit `cores.txt` to configure builds. Cores are grouped by system, with disabled
entries left in place when the pinned `libretro-super` checkout lacks a build
rule or the current PSC toolchain is missing required dependencies.

Per-core PSC build fixes live in `scripts/core-fixes/`. The main container entry
point is `scripts/build-core.sh`; a root `/build/build-core.sh` symlink is kept
inside the Docker image for compatibility.

## Build

Self-contained Docker build with crosstool-ng toolchain:

| Component | Value |
|-----------|-------|
| Compiler | GCC 9, glibc 2.23 |
| Target | ARM Cortex-A35 (ARMv8-A, hard-float, NEON) |
| Flags | `-O3 -march=armv8-a -mtune=cortex-a35 -mfpu=neon-fp-armv8` |

## Versioning

```bash
make check-version                    # Compare pinned vs latest
make LIBRETRO_SUPER_REF=<commit>      # Build specific version
make release                          # Creates libretro-cores-psc-<date>-<commit>.tar.gz
```

## License

MIT
