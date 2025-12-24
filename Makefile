# Libretro Cores PSC - Build System
# Fully self-contained: builds toolchain from scratch
#
# Usage:
#   make                    - Build cores (skips existing)
#   make FORCE=1            - Rebuild all cores
#   make CORE=snes9x        - Build single core
#   make PARALLEL=8         - Build 8 cores simultaneously
#   make list               - List available cores
#   make shell              - Interactive container

IMAGE_NAME := libretro-cores-psc
OUTPUT_DIR := cores_output
RELEASE_DIR := releases
CORE ?=

# Version pinning (override with: make LIBRETRO_SUPER_REF=<commit>)
LIBRETRO_SUPER_REF ?=

# Parallel core builds (default: half of available CPUs)
PARALLEL ?= $(shell echo $$(( $$(nproc) / 2 )))

# Jobs per core build (uses remaining CPUs)
JOBS_PER_CORE ?= $(shell echo $$(( $$(nproc) / $(PARALLEL) )))

.PHONY: all build image shell clean list help parallel-build version release package

# Default: build all cores from cores.txt
all: image
	@if [ -n "$(CORE)" ]; then \
		$(MAKE) build-single CORE=$(CORE); \
	else \
		$(MAKE) parallel-build; \
	fi

# Build Docker image (includes toolchain build, cached after first run)
image:
	@echo "Building Docker image (includes crosstool-ng toolchain)..."
	@echo "First build compiles toolchain from scratch, subsequent builds use cache."
	docker build -t $(IMAGE_NAME) \
		$(if $(LIBRETRO_SUPER_REF),--build-arg LIBRETRO_SUPER_REF=$(LIBRETRO_SUPER_REF)) \
		.

# Show version info
version:
	@echo "libretro-super: $$(grep -oP 'ARG LIBRETRO_SUPER_REF=\K.{7}' Dockerfile)"
	@if [ -f $(OUTPUT_DIR)/VERSION ]; then \
		. $(OUTPUT_DIR)/VERSION && \
		echo "Version: $${libretro_super_date}-$${libretro_super_commit}"; \
	else \
		echo "Version: (run 'make' to determine date)"; \
	fi

# Write version info to output directory
version-info: image
	@mkdir -p $(OUTPUT_DIR)
	@echo "Fetching libretro-super version info..."
	@docker run --rm $(IMAGE_NAME) sh -c '\
		cd /build/libretro-super && \
		echo "libretro_super_commit=$$(git rev-parse --short HEAD)" && \
		echo "libretro_super_date=$$(git log -1 --format=%cd --date=short)" && \
		echo "build_date=$$(date -u +%Y-%m-%d)" && \
		echo "toolchain=crosstool-ng-gcc9-glibc2.23" && \
		echo "target=armv8-a-cortex-a35-neon"' > $(OUTPUT_DIR)/VERSION
	@cat $(OUTPUT_DIR)/VERSION

# Package cores for release
# Filename format: libretro-cores-psc-{date}-{commit}.tar.gz
package:
	@if [ ! -d $(OUTPUT_DIR) ] || [ -z "$$(ls -A $(OUTPUT_DIR)/*.so 2>/dev/null)" ]; then \
		echo "Error: No cores built. Run 'make' first."; \
		exit 1; \
	fi
	@if [ ! -f $(OUTPUT_DIR)/VERSION ]; then \
		echo "Error: VERSION file not found. Run 'make' first."; \
		exit 1; \
	fi
	@mkdir -p $(RELEASE_DIR)
	@. $(OUTPUT_DIR)/VERSION && \
	RELEASE_NAME="libretro-cores-psc-$${libretro_super_date}-$${libretro_super_commit}" && \
	echo "Creating release: $${RELEASE_NAME}.tar.gz" && \
	tar -czvf $(RELEASE_DIR)/$${RELEASE_NAME}.tar.gz -C $(OUTPUT_DIR) . && \
	echo "Created: $(RELEASE_DIR)/$${RELEASE_NAME}.tar.gz"

# Full release: build + package
release: all package

# Build all cores in parallel using GNU parallel or xargs
# Use FORCE=1 to rebuild all cores (ignores existing .so files)
parallel-build: image version-info
	@mkdir -p $(OUTPUT_DIR)
	@if [ ! -f cores.txt ]; then \
		echo "Error: cores.txt not found"; \
		exit 1; \
	fi
	@rm -f $(OUTPUT_DIR)/failed.txt $(OUTPUT_DIR)/success.txt $(OUTPUT_DIR)/skipped.txt
	@echo "=== Building cores ($(PARALLEL) parallel, $(JOBS_PER_CORE) jobs each) ==="
	@sed 's/#.*//' cores.txt | grep -v '^$$' | tr -d ' \t' | grep -v '^$$' | \
		xargs -P $(PARALLEL) -I {} sh -c ' \
			if [ -z "$(FORCE)" ] && [ -f "$(OUTPUT_DIR)/{}_libretro.so" ]; then \
				echo "--- Skipping: {} (already built)"; \
				echo "{}" >> $(OUTPUT_DIR)/skipped.txt; \
			else \
				echo ">>> Building: {}"; \
				docker run --rm \
					-e JOBS=$(JOBS_PER_CORE) \
					-v $(PWD)/$(OUTPUT_DIR):/build/output \
					$(IMAGE_NAME) \
					/build/build-core.sh "{}" 2>&1 | tail -5; \
				if [ -f "$(OUTPUT_DIR)/{}_libretro.so" ]; then \
					echo "<<< Done: {}"; \
					echo "{}" >> $(OUTPUT_DIR)/success.txt; \
				else \
					echo "<<< FAILED: {}"; \
					echo "{}" >> $(OUTPUT_DIR)/failed.txt; \
				fi \
			fi \
		'
	@echo ""
	@echo "=== Build Complete ==="
	@echo "Skipped: $$(cat $(OUTPUT_DIR)/skipped.txt 2>/dev/null | wc -l) (already built)"
	@echo "Successful: $$(cat $(OUTPUT_DIR)/success.txt 2>/dev/null | wc -l)"
	@echo "Failed: $$(cat $(OUTPUT_DIR)/failed.txt 2>/dev/null | wc -l)"
	@if [ -f $(OUTPUT_DIR)/failed.txt ]; then \
		echo ""; \
		echo "Failed cores:"; \
		cat $(OUTPUT_DIR)/failed.txt | sed 's/^/  /'; \
	fi
	@echo ""
	@echo "Total size:"
	@du -sh $(OUTPUT_DIR)/ 2>/dev/null || echo "0"

# Build all cores sequentially (old behavior)
build-all: image
	@mkdir -p $(OUTPUT_DIR)
	@if [ ! -f cores.txt ]; then \
		echo "Error: cores.txt not found"; \
		exit 1; \
	fi
	@while read -r core; do \
		[ -z "$$core" ] && continue; \
		case "$$core" in \#*) continue;; esac; \
		echo "=== Building $$core ==="; \
		docker run --rm \
			-v $(PWD)/$(OUTPUT_DIR):/build/output \
			$(IMAGE_NAME) \
			/build/build-core.sh "$$core" || echo "Warning: $$core failed"; \
	done < cores.txt
	@echo "=== All cores built ==="
	@ls -lh $(OUTPUT_DIR)/

# Build single core
build-single: image
	@mkdir -p $(OUTPUT_DIR)
	docker run --rm \
		-v $(PWD)/$(OUTPUT_DIR):/build/output \
		$(IMAGE_NAME) \
		/build/build-core.sh "$(CORE)"

# Debug build - full output for troubleshooting
debug: image
	@if [ -z "$(CORE)" ]; then echo "Usage: make debug CORE=<name>"; exit 1; fi
	@mkdir -p $(OUTPUT_DIR)
	@mkdir -p logs
	docker run --rm \
		-v $(PWD)/$(OUTPUT_DIR):/build/output \
		$(IMAGE_NAME) \
		/build/build-core.sh "$(CORE)" 2>&1 | tee logs/$(CORE).log
	@echo "Full log saved to: logs/$(CORE).log"

# Interactive shell in container
shell: image
	docker run --rm -it \
		-v $(PWD)/$(OUTPUT_DIR):/build/output \
		$(IMAGE_NAME) \
		/bin/bash

# List available cores (from libretro-super)
list: image
	@docker run --rm $(IMAGE_NAME) \
		ls /build/libretro-super/recipes/*/

# Clean output
clean:
	rm -rf $(OUTPUT_DIR) $(RELEASE_DIR) logs

# Deep clean (remove image too)
distclean: clean
	docker rmi $(IMAGE_NAME) 2>/dev/null || true

# Show core info
info:
	@echo "Image: $(IMAGE_NAME)"
	@echo "Output: $(OUTPUT_DIR)"
	@echo "Core: $(CORE)"
	@echo "Parallel builds: $(PARALLEL)"
	@echo "Jobs per core: $(JOBS_PER_CORE)"
	@echo "Total CPUs: $$(nproc)"
	@if [ -f cores.txt ]; then \
		echo "Cores in cores.txt: $$(sed 's/#.*//' cores.txt | tr -d ' \t' | grep -v '^$$' | wc -l)"; \
	fi

# Show build status
status:
	@echo "=== Build Summary ==="
	@echo "Successful: $$(ls -1 $(OUTPUT_DIR)/*.so 2>/dev/null | wc -l) cores"
	@if [ -f $(OUTPUT_DIR)/failed.txt ]; then \
		echo "Failed: $$(cat $(OUTPUT_DIR)/failed.txt | wc -l) cores"; \
	fi
	@echo ""
	@if [ -f $(OUTPUT_DIR)/failed.txt ]; then \
		echo "=== Failed Cores ($(OUTPUT_DIR)/failed.txt) ==="; \
		cat $(OUTPUT_DIR)/failed.txt | sed 's/^/  /'; \
		echo ""; \
	fi
	@echo "=== Missing Cores ==="
	@if [ -f cores.txt ]; then \
		MISSING=0; \
		sed 's/#.*//' cores.txt | tr -d ' \t' | grep -v '^$$' | while read core; do \
			if [ ! -f "$(OUTPUT_DIR)/$${core}_libretro.so" ]; then \
				echo "  $$core"; \
			fi; \
		done; \
	fi

# Retry failed cores (uses failed.txt if available)
retry-failed: image
	@mkdir -p $(OUTPUT_DIR)
	@if [ -f $(OUTPUT_DIR)/failed.txt ]; then \
		echo "=== Retrying $$(cat $(OUTPUT_DIR)/failed.txt | wc -l) failed cores ==="; \
		cat $(OUTPUT_DIR)/failed.txt | while read core; do \
			echo ">>> Retrying: $$core"; \
			docker run --rm \
				-v $(PWD)/$(OUTPUT_DIR):/build/output \
				$(IMAGE_NAME) \
				/build/build-core.sh "$$core" && \
				sed -i "/^$$core$$/d" $(OUTPUT_DIR)/failed.txt || \
				echo "Still failed: $$core"; \
		done; \
	else \
		echo "No failed.txt found. Checking for missing cores..."; \
		sed 's/#.*//' cores.txt | tr -d ' \t' | grep -v '^$$' | while read core; do \
			if [ ! -f "$(OUTPUT_DIR)/$${core}_libretro.so" ]; then \
				echo ">>> Retrying: $$core"; \
				docker run --rm \
					-v $(PWD)/$(OUTPUT_DIR):/build/output \
					$(IMAGE_NAME) \
					/build/build-core.sh "$$core" || echo "Failed: $$core"; \
			fi; \
		done; \
	fi

# Show latest libretro-super commit
check-version:
	@echo "Current pinned version in Dockerfile:"
	@grep "ARG LIBRETRO_SUPER_REF=" Dockerfile | head -1
	@echo ""
	@echo "Latest upstream:"
	@git ls-remote https://github.com/libretro/libretro-super.git HEAD

help:
	@echo "Libretro Cores PSC Build System"
	@echo ""
	@echo "Usage:"
	@echo "  make                     Build all cores (skips existing)"
	@echo "  make FORCE=1             Rebuild all cores"
	@echo "  make CORE=snes9x         Build single core"
	@echo "  make PARALLEL=16         Build 16 cores simultaneously"
	@echo "  make build-all           Build all cores sequentially"
	@echo "  make shell               Interactive container shell"
	@echo "  make list                List available cores"
	@echo "  make status              Show build status"
	@echo "  make retry-failed        Rebuild failed cores"
	@echo "  make debug CORE=<name>   Debug build with full log"
	@echo "  make clean               Remove built cores and releases"
	@echo "  make distclean           Remove cores, releases, and Docker image"
	@echo "  make info                Show build configuration"
	@echo "  make check-version       Show libretro-super version info"
	@echo ""
	@echo "Release:"
	@echo "  make version             Show version info"
	@echo "  make version-info        Write VERSION file to output"
	@echo "  make package             Package built cores into release archive"
	@echo "  make release             Full release: build all + package"
	@echo ""
	@echo "Version override:"
	@echo "  make LIBRETRO_SUPER_REF=<commit> - Use specific libretro-super version"
	@echo ""
	@echo "Server optimization:"
	@echo "  On a 64-core server: make PARALLEL=32"
	@echo "  This builds 32 cores at once, each using 2 jobs"
	@echo ""
	@echo "Examples:"
	@echo "  make CORE=genesis_plus_gx"
	@echo "  make PARALLEL=8 JOBS_PER_CORE=4"
	@echo "  make release             # Build all and create release"
	@echo "  make package             # Package existing builds"
	@echo ""
	@echo "Release naming: libretro-cores-psc-{date}-{commit}.tar.gz"
	@echo "  Example: libretro-cores-psc-2024-12-15-6244066.tar.gz"
