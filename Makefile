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

.PHONY: all lake configure build test install lite serve deploy clean

all: build test

# Generate .c files from Lean source (required before cmake)
lake:
	lake build REPL WasmRepl

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

clean:
	rm -rf $(BUILD_DIR) $(OUTPUT_DIR) .jupyterlite.doit.db
