# xeus-lean WASM Build & Deploy
# ==============================
# Usage:
#   make all           # Full dev cycle: lake + configure + build + test
#   make deploy        # Full pipeline: build + install + lite + serve
#   make test          # Run WASM tests in Node.js
#   make serve         # Serve existing _output on port 8888
#   make clean         # Remove build artifacts
#
# Prerequisites: nix (provides emscripten, cmake, nodejs_24, python3)

NPROCS := $(shell sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)
BUILD_DIR := wasm-build
OUTPUT_DIR := _output
PORT := 8888
WASM_HOST_PREFIX := $(CURDIR)/.pixi/envs/wasm-host

# nix-shell wrapper — provides emscripten, cmake, node 24, python3
# Unsets nix linker flags that break wasm-ld.
NIX_SHELL := nix-shell -p emscripten cmake gnumake python3 nodejs_24 llvmPackages.bintools-unwrapped --run

# pixi wrapper — provides jupyterlite (not available in nix)
PIXI_SHELL := nix-shell -p pixi --run

.PHONY: all lake configure build test install lite serve deploy clean \
        e2e-install e2e-test e2e-update e2e-ui \
        docker-wasm-builder docker-e2e-image \
        e2e-docker e2e-docker-update e2e-docker-report

all: build test

# Generate .c files from Lean source (required before cmake)
lake:
	lake build REPL Display WasmRepl

configure: lake
	$(NIX_SHELL) '\
		unset LDFLAGS LDFLAGS_LD NIX_LDFLAGS 2>/dev/null; \
		emcmake cmake -S . -B $(BUILD_DIR) \
		  -DCMAKE_BUILD_TYPE=Release \
		  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ON'

build: configure
	$(NIX_SHELL) '\
		unset LDFLAGS LDFLAGS_LD NIX_LDFLAGS 2>/dev/null; \
		emmake make -C $(BUILD_DIR) -j$(NPROCS) xlean test_wasm_node'

test: build
	$(NIX_SHELL) '\
		node --experimental-wasm-memory64 $(BUILD_DIR)/test_wasm_node.js'

install: build
	cmake --install $(BUILD_DIR) --prefix $(WASM_HOST_PREFIX)
	# Rewrite kernel.json to use an absolute path. jupyterlite-xeus
	# reads argv[0] verbatim and then appends ".js"/".wasm" to locate
	# the kernel binaries, so the path must resolve from any CWD.
	python3 -c "import json,os,pathlib; \
p=pathlib.Path('$(WASM_HOST_PREFIX)/share/jupyter/kernels/xlean/kernel.json'); \
spec=json.loads(p.read_text()); \
spec['argv']=[os.path.abspath('$(WASM_HOST_PREFIX)/bin/xlean')]; \
p.write_text(json.dumps(spec, indent=2))"

lite: install
	rm -rf $(OUTPUT_DIR) .jupyterlite.doit.db
	$(PIXI_SHELL) '\
		pixi run -e wasm-build jupyter lite build \
		  --XeusAddon.prefix=$(WASM_HOST_PREFIX) \
		  "--XeusAddon.default_channels=[https://conda.anaconda.org/conda-forge]" \
		  --contents notebooks \
		  --output-dir $(OUTPUT_DIR) \
		  --force'

serve:
	@-lsof -ti:$(PORT) | xargs kill -9 2>/dev/null; sleep 1
	cd $(OUTPUT_DIR) && python3 ../serve_nocache.py $(PORT)

deploy: lite serve

# ---- End-to-end tests (Playwright) ----------------------------------
#
# These tests drive the built _output/ site with a headless Chromium.
#
# Two execution modes:
#
#   make e2e-docker       Build a WASM image + a Playwright image, run
#                         inside containers. Fully hermetic; required on
#                         NixOS because the prebuilt Chromium binaries
#                         Playwright downloads cannot run on NixOS hosts
#                         without patching. This is the recommended path.
#
#   make e2e-test         Native path: use the host's Node.js and a
#                         locally-built _output/. Fast if you already
#                         have the build, but fragile on NixOS. Run
#                         `make e2e-install` once beforehand.

# --- Docker-based E2E (recommended, hermetic) ---
E2E_BUILDER_IMAGE := xeus-lean-wasm-builder
E2E_IMAGE := xeus-lean-e2e

docker-wasm-builder:
	docker build -f Dockerfile.wasm -t $(E2E_BUILDER_IMAGE) --target builder .

docker-e2e-image: docker-wasm-builder
	docker build -f Dockerfile.e2e -t $(E2E_IMAGE) .

e2e-docker: docker-e2e-image
	docker run --rm --init $(E2E_IMAGE)

e2e-docker-update: docker-e2e-image
	# Regenerate snapshots inside the container, then copy them back.
	CID=$$(docker create --init -e UPDATE_SNAPSHOTS=1 $(E2E_IMAGE)) && \
	docker start -a $$CID; RC=$$?; \
	docker cp $$CID:/work/tests/e2e/__snapshots__ tests/e2e/ 2>/dev/null || true; \
	docker rm $$CID >/dev/null; \
	exit $$RC

e2e-docker-report: docker-e2e-image
	# Copy the HTML report out after a failing run.
	CID=$$(docker create --init $(E2E_IMAGE)) && \
	docker start -a $$CID; RC=$$?; \
	docker cp $$CID:/work/tests/e2e/playwright-report tests/e2e/ 2>/dev/null || true; \
	docker cp $$CID:/work/tests/e2e/test-results tests/e2e/ 2>/dev/null || true; \
	docker rm $$CID >/dev/null; \
	exit $$RC

# --- Native (non-Docker) E2E, for non-NixOS hosts ---
e2e-install:
	cd tests/e2e && npm install && npx playwright install --with-deps chromium

e2e-test: lite
	cd tests/e2e && npx playwright test

e2e-update: lite
	cd tests/e2e && UPDATE_SNAPSHOTS=1 npx playwright test

e2e-ui: lite
	cd tests/e2e && npx playwright test --ui

clean:
	rm -rf $(BUILD_DIR) $(OUTPUT_DIR) .jupyterlite.doit.db
	rm -rf tests/e2e/test-results tests/e2e/playwright-report
