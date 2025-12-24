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
make release             # Create release archive
make help                # Show all commands
```

Output: `cores_output/*.so`

## Cores

Edit `cores.txt` to configure builds. Organized by PSC performance:

| Tier | Systems |
|------|---------|
| **1 - Full speed** | NES, SNES, Genesis, PC Engine, GB/GBA, Neo Geo, CPS1/2 |
| **2 - Great** | PS1, Arcade, Amiga, DOS, C64, MSX |
| **3 - Experimental** | 3DO, Jaguar, Atari ST |
| **4 - Heavy** | N64, Saturn, Dreamcast, PSP |

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
