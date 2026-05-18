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
METADATA_DIR := build_metadata
COMMIT_DIR := $(METADATA_DIR)/commits
STATUS_DIR := build_status
FAILED_FILE := $(STATUS_DIR)/failed.txt
SUCCESS_FILE := $(STATUS_DIR)/success.txt
SKIPPED_FILE := $(STATUS_DIR)/skipped.txt
RELEASE_DIR := releases
CORE ?=

# Version pinning (override with: make LIBRETRO_SUPER_REF=<commit>)
LIBRETRO_SUPER_REF ?=

# Parallel core builds (default: half of available CPUs)
PARALLEL ?= $(shell n=$$(nproc); p=$$(( (n + 1) / 2 )); [ $$p -lt 1 ] && p=1; echo $$p)

# Jobs per core build (uses remaining CPUs)
JOBS_PER_CORE ?= $(shell n=$$(nproc); j=$$(( n / $(PARALLEL) )); [ $$j -lt 1 ] && j=1; echo $$j)

.PHONY: all image version version-info package release parallel-build commits build-all build-single debug shell list audit-cores clean distclean info status retry-failed check-version help

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
	@if [ -f $(METADATA_DIR)/VERSION ]; then \
		. $(METADATA_DIR)/VERSION && \
		echo "Version: $${libretro_super_date}-$${libretro_super_commit}"; \
	else \
		echo "Version: (run 'make' to determine date)"; \
	fi

# Write version info to metadata directory
version-info: image
	@mkdir -p $(METADATA_DIR)
	@echo "Fetching libretro-super version info..."
	@docker run --rm $(IMAGE_NAME) sh -c '\
		cd /build/libretro-super && \
		echo "libretro_super_commit=$$(git rev-parse --short HEAD)" && \
		echo "libretro_super_date=$$(git log -1 --format=%cd --date=short)" && \
		echo "build_date=$$(date -u +%Y-%m-%d)" && \
		echo "toolchain=crosstool-ng-gcc9-glibc2.23" && \
		echo "target=armv8-a-cortex-a35-neon"' > $(METADATA_DIR)/VERSION
	@cat $(METADATA_DIR)/VERSION

# Package cores for release
# Filename format: libretro-cores-psc-{date}-{commit}.tar.gz
package:
	@if [ ! -d $(OUTPUT_DIR) ] || [ -z "$$(ls -A $(OUTPUT_DIR)/*.so 2>/dev/null)" ]; then \
		echo "Error: No cores built. Run 'make' first."; \
		exit 1; \
	fi
	@if [ ! -f $(METADATA_DIR)/VERSION ]; then \
		echo "Error: VERSION file not found. Run 'make' first."; \
		exit 1; \
	fi
	@mkdir -p $(RELEASE_DIR)
	@$(MAKE) --no-print-directory commits
	@if [ ! -f $(METADATA_DIR)/COMMITS.txt ]; then \
		echo "Error: COMMITS.txt file not found. Build at least one core first."; \
		exit 1; \
	fi
	@missing=$$(sed 's/#.*//' cores.txt | tr -d ' \t' | grep -v '^$$' | while read -r core; do \
		[ -f "$(OUTPUT_DIR)/$${core}_libretro.so" ] || echo "$$core"; \
	done); \
	if [ -n "$$missing" ]; then \
		echo "Error: enabled cores in cores.txt are missing .so output:"; \
		echo "$$missing" | sed 's/^/  /'; \
		echo "Run 'make' or 'make retry-failed' before packaging."; \
		exit 1; \
	fi
	@. $(METADATA_DIR)/VERSION && \
		RELEASE_NAME="libretro-cores-psc-$${libretro_super_date}-$${libretro_super_commit}" && \
		echo "Creating release: $${RELEASE_NAME}.tar.gz" && \
		tmp=$$(mktemp -d) && \
		trap "rm -rf $$tmp" EXIT && \
		sed 's/#.*//' cores.txt | tr -d ' \t' | grep -v '^$$' | while read -r core; do \
			cp "$(OUTPUT_DIR)/$${core}_libretro.so" "$$tmp/"; \
		done && \
		cp $(METADATA_DIR)/VERSION $(METADATA_DIR)/COMMITS.txt "$$tmp/" && \
		tar -czvf $(RELEASE_DIR)/$${RELEASE_NAME}.tar.gz -C "$$tmp" . && \
		echo "Created: $(RELEASE_DIR)/$${RELEASE_NAME}.tar.gz"

# Full release: build + package
release: all package

# Build all cores in parallel using GNU parallel or xargs
# Use FORCE=1 to rebuild all cores (ignores existing .so files)
parallel-build: image version-info
	@mkdir -p $(OUTPUT_DIR) $(METADATA_DIR) $(STATUS_DIR)
	@if [ ! -f cores.txt ]; then \
		echo "Error: cores.txt not found"; \
		exit 1; \
	fi
	@rm -f $(FAILED_FILE) $(SUCCESS_FILE) $(SKIPPED_FILE)
	@echo "=== Building cores ($(PARALLEL) parallel, $(JOBS_PER_CORE) jobs each) ==="
	@sed 's/#.*//' cores.txt | tr -d ' \t' | grep -v '^$$' | \
		xargs -P $(PARALLEL) -I {} sh -c ' \
			if [ -z "$(FORCE)" ] && [ -f "$(OUTPUT_DIR)/{}_libretro.so" ]; then \
				echo "--- Skipping: {} (already built)"; \
				echo "{}" >> $(SKIPPED_FILE); \
			else \
				echo ">>> Building: {}"; \
				rm -f "$(OUTPUT_DIR)/{}_libretro.so"; \
				docker run --rm \
					-e JOBS=$(JOBS_PER_CORE) \
					-v $(PWD)/$(OUTPUT_DIR):/build/output \
					-v $(PWD)/$(METADATA_DIR):/build/metadata \
					$(IMAGE_NAME) \
					/build/build-core.sh "{}" 2>&1 | tail -5; \
				if [ -f "$(OUTPUT_DIR)/{}_libretro.so" ]; then \
					echo "<<< Done: {}"; \
					echo "{}" >> $(SUCCESS_FILE); \
				else \
					echo "<<< FAILED: {}"; \
					echo "{}" >> $(FAILED_FILE); \
				fi \
			fi \
		'
	@echo ""
	@echo "=== Build Complete ==="
	@echo "Skipped: $$(cat $(SKIPPED_FILE) 2>/dev/null | wc -l) (already built)"
	@echo "Successful: $$(cat $(SUCCESS_FILE) 2>/dev/null | wc -l)"
	@echo "Failed: $$(cat $(FAILED_FILE) 2>/dev/null | wc -l)"
	@if [ -f $(FAILED_FILE) ]; then \
		echo ""; \
		echo "Failed cores:"; \
		cat $(FAILED_FILE) | sed 's/^/  /'; \
	fi
	@$(MAKE) --no-print-directory commits
	@echo ""
	@echo "Total size:"
	@du -sh $(OUTPUT_DIR)/ 2>/dev/null || echo "0"

# Aggregate per-core .so.commit sidecar files into COMMITS.txt
# Format: <core> <short_commit> <full_commit> <url>
commits:
	@mkdir -p $(METADATA_DIR) $(COMMIT_DIR)
	@if [ -d $(OUTPUT_DIR)/.metadata/commits ]; then find $(OUTPUT_DIR)/.metadata/commits -maxdepth 1 -type f -name '*.so.commit' -exec mv -f {} $(COMMIT_DIR)/ \;; fi
	@if ls $(COMMIT_DIR)/*.so.commit >/dev/null 2>&1; then \
		echo "" ; \
		echo "=== Aggregating commit info ==="; \
		: > $(METADATA_DIR)/COMMITS.txt; \
		for f in $(COMMIT_DIR)/*.so.commit; do \
			core=$$(grep '^core=' "$$f" | cut -d= -f2); \
			commit=$$(grep '^commit=' "$$f" | cut -d= -f2); \
			url=$$(grep '^url=' "$$f" | cut -d= -f2-); \
			short=$$(echo "$$commit" | cut -c1-7); \
			printf '%-32s %s %s %s\n' "$$core" "$$short" "$$commit" "$$url" >> $(METADATA_DIR)/COMMITS.txt; \
		done; \
		sort -o $(METADATA_DIR)/COMMITS.txt $(METADATA_DIR)/COMMITS.txt; \
		echo "Wrote $(METADATA_DIR)/COMMITS.txt ($$(wc -l < $(METADATA_DIR)/COMMITS.txt) cores)"; \
	fi

# Build all cores sequentially (old behavior)
build-all: image
	@mkdir -p $(OUTPUT_DIR) $(METADATA_DIR) $(STATUS_DIR)
	@if [ ! -f cores.txt ]; then \
		echo "Error: cores.txt not found"; \
		exit 1; \
	fi
	@rm -f $(FAILED_FILE) $(SUCCESS_FILE) $(SKIPPED_FILE)
	@sed 's/#.*//' cores.txt | tr -d ' \t' | grep -v '^$$' | while read -r core; do \
		echo "=== Building $$core ==="; \
		docker run --rm \
			-v $(PWD)/$(OUTPUT_DIR):/build/output \
			-v $(PWD)/$(METADATA_DIR):/build/metadata \
			$(IMAGE_NAME) \
			/build/build-core.sh "$$core" || true; \
		if [ -f "$(OUTPUT_DIR)/$${core}_libretro.so" ]; then \
			echo "$$core" >> $(SUCCESS_FILE); \
		else \
			echo "Warning: $$core failed"; \
			echo "$$core" >> $(FAILED_FILE); \
		fi; \
	done
	@$(MAKE) --no-print-directory commits
	@echo "=== All cores built ==="
	@ls -lh $(OUTPUT_DIR)/

# Build single core
build-single: image
	@mkdir -p $(OUTPUT_DIR) $(METADATA_DIR)
	docker run --rm \
		-v $(PWD)/$(OUTPUT_DIR):/build/output \
		-v $(PWD)/$(METADATA_DIR):/build/metadata \
		$(IMAGE_NAME) \
		/build/build-core.sh "$(CORE)"
	@$(MAKE) --no-print-directory commits

# Debug build - full output for troubleshooting
debug: image
	@if [ -z "$(CORE)" ]; then echo "Usage: make debug CORE=<name>"; exit 1; fi
	@mkdir -p $(OUTPUT_DIR)
	@mkdir -p $(METADATA_DIR)
	@mkdir -p logs
	docker run --rm \
		-v $(PWD)/$(OUTPUT_DIR):/build/output \
		-v $(PWD)/$(METADATA_DIR):/build/metadata \
		$(IMAGE_NAME) \
		/build/build-core.sh "$(CORE)" 2>&1 | tee logs/$(CORE).log
	@$(MAKE) --no-print-directory commits
	@echo "Full log saved to: logs/$(CORE).log"

# Interactive shell in container
shell: image
	@mkdir -p $(OUTPUT_DIR) $(METADATA_DIR)
	docker run --rm -it \
		-v $(PWD)/$(OUTPUT_DIR):/build/output \
		-v $(PWD)/$(METADATA_DIR):/build/metadata \
		$(IMAGE_NAME) \
		/bin/bash

# List available cores (from libretro-super)
list: image
	@docker run --rm $(IMAGE_NAME) \
		ls /build/libretro-super/recipes/*/

# Compare cores.txt against the pinned libretro-super core rule list.
audit-cores: image
	@docker run --rm \
		-v $(PWD)/cores.txt:/build/cores.txt:ro \
		$(IMAGE_NAME) \
		/build/scripts/audit-cores.sh /build/cores.txt /build/libretro-super

# Clean output
clean:
	rm -rf $(OUTPUT_DIR) $(METADATA_DIR) $(STATUS_DIR) $(RELEASE_DIR) logs

# Deep clean (remove image too)
distclean: clean
	docker rmi $(IMAGE_NAME) 2>/dev/null || true

# Show core info
info:
	@echo "Image: $(IMAGE_NAME)"
	@echo "Output: $(OUTPUT_DIR)"
	@echo "Metadata: $(METADATA_DIR)"
	@echo "Status: $(STATUS_DIR)"
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
	@echo "Built output files: $$(ls -1 $(OUTPUT_DIR)/*.so 2>/dev/null | wc -l)"
	@if [ -f cores.txt ]; then \
		enabled=$$(sed 's/#.*//' cores.txt | tr -d ' \t' | grep -v '^$$' | wc -l); \
		built=$$(sed 's/#.*//' cores.txt | tr -d ' \t' | grep -v '^$$' | while read -r core; do \
			[ -f "$(OUTPUT_DIR)/$${core}_libretro.so" ] && echo "$$core"; \
		done | wc -l); \
		echo "Enabled built: $$built/$$enabled cores"; \
	fi
	@echo "With commit info: $$(ls -1 $(COMMIT_DIR)/*.so.commit 2>/dev/null | wc -l) cores"
	@if [ -f $(METADATA_DIR)/VERSION ]; then echo "Version file: $(METADATA_DIR)/VERSION"; fi
	@if [ -f $(METADATA_DIR)/COMMITS.txt ]; then echo "Commit manifest: $(METADATA_DIR)/COMMITS.txt"; fi
	@if [ -d $(STATUS_DIR) ]; then echo "Status files: $(STATUS_DIR)/"; else echo "Status files: none yet (run make or make build-all)"; fi
	@if [ -f $(FAILED_FILE) ]; then \
		unresolved=$$(sed 's/#.*//' cores.txt | tr -d ' \t' | grep -v '^$$' | while read -r core; do \
			if grep -Fxq "$$core" $(FAILED_FILE) && [ ! -f "$(OUTPUT_DIR)/$${core}_libretro.so" ]; then echo "$$core"; fi; \
		done | wc -l); \
		echo "Failed from last run: $$(cat $(FAILED_FILE) | wc -l) cores ($$unresolved enabled and unresolved)"; \
	fi
	@echo ""
	@if [ -f $(FAILED_FILE) ]; then \
		echo "=== Unresolved Failed Cores ($(FAILED_FILE)) ==="; \
		sed 's/#.*//' cores.txt | tr -d ' \t' | grep -v '^$$' | while read -r core; do \
			if grep -Fxq "$$core" $(FAILED_FILE) && [ ! -f "$(OUTPUT_DIR)/$${core}_libretro.so" ]; then echo "  $$core"; fi; \
		done; \
		echo ""; \
	fi
	@echo "=== Missing Cores ==="
	@if [ -f cores.txt ]; then \
		tmp=$$(mktemp); \
		sed 's/#.*//' cores.txt | tr -d ' \t' | grep -v '^$$' | while read core; do \
			if [ ! -f "$(OUTPUT_DIR)/$${core}_libretro.so" ]; then \
				echo "  $$core"; \
			fi; \
		done > "$$tmp"; \
		if [ -s "$$tmp" ]; then cat "$$tmp"; else echo "  none"; fi; \
		rm -f "$$tmp"; \
	fi

# Retry failed cores (uses build_status/failed.txt if available)
retry-failed: image
	@mkdir -p $(OUTPUT_DIR) $(METADATA_DIR) $(STATUS_DIR)
	@if [ -f $(FAILED_FILE) ]; then \
		tmp=$$(mktemp); \
		sed 's/#.*//' cores.txt | tr -d ' \t' | grep -v '^$$' | while read -r core; do \
			if grep -Fxq "$$core" $(FAILED_FILE) && [ ! -f "$(OUTPUT_DIR)/$${core}_libretro.so" ]; then echo "$$core"; fi; \
		done > "$$tmp"; \
		echo "=== Retrying $$(cat "$$tmp" | wc -l) unresolved failed cores ==="; \
		cat "$$tmp" | while read core; do \
			echo ">>> Retrying: $$core"; \
			docker run --rm \
				-v $(PWD)/$(OUTPUT_DIR):/build/output \
				-v $(PWD)/$(METADATA_DIR):/build/metadata \
				$(IMAGE_NAME) \
				/build/build-core.sh "$$core" && \
				sed -i "/^$$core$$/d" $(FAILED_FILE) || \
				echo "Still failed: $$core"; \
		done; \
		rm -f "$$tmp"; \
	else \
		echo "No failed.txt found. Checking for missing cores..."; \
		sed 's/#.*//' cores.txt | tr -d ' \t' | grep -v '^$$' | while read core; do \
			if [ ! -f "$(OUTPUT_DIR)/$${core}_libretro.so" ]; then \
				echo ">>> Retrying: $$core"; \
				docker run --rm \
					-v $(PWD)/$(OUTPUT_DIR):/build/output \
					-v $(PWD)/$(METADATA_DIR):/build/metadata \
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
	@echo "  make audit-cores         Compare cores.txt with supported libretro-super rules"
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
	@echo "  make version-info        Write VERSION file to metadata"
	@echo "  make commits             Aggregate per-core commits into COMMITS.txt"
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
