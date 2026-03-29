# Deployment Guide

## GitHub Pages Setup

To enable automatic deployment to GitHub Pages, you need to configure your repository settings:

### Steps to Enable GitHub Pages

1. Go to your repository on GitHub
2. Navigate to **Settings** → **Pages**
3. Under **Source**, select **GitHub Actions** from the dropdown
4. Save the settings

The URL will be: `https://<username>.github.io/xeus-lean/`

### How It Works

The CI workflow (`.github/workflows/ci.yml`) automatically:

1. **WASM Build Job**: Builds the JupyterLite site with the xeus-lean WASM kernel
2. **Deploy Pages Job**: Deploys the built site to GitHub Pages (only on main branch pushes)

### Troubleshooting

#### Error: "Not Found" (404) during deployment

This means GitHub Pages is not enabled or not configured to use GitHub Actions as the source.

**Solution**: Follow the steps above to enable GitHub Pages with "GitHub Actions" as the source.

#### Error: Permission denied

Ensure the repository has the following workflow permissions:
- Go to **Settings** → **Actions** → **General**
- Under **Workflow permissions**, select **Read and write permissions**
- Check **Allow GitHub Actions to create and approve pull requests**

#### Build succeeds but deployment fails

Check that:
1. The `wasm-build` job completes successfully
2. The `upload-pages-artifact` step in the `wasm-build` job runs
3. The artifact named `github-pages` is created
4. GitHub Pages is enabled with the correct source

### Local Testing

Before deploying, you can test the JupyterLite site locally:

```bash
# Using pixi
pixi install -e wasm-build --no-lockfile-update
pixi install -e wasm-host --no-lockfile-update
pixi run -e wasm-build fix-emscripten-links
lake build REPL WasmRepl
pixi run -e wasm-build emcmake cmake -S . -B wasm-build -DCMAKE_BUILD_TYPE=Release
pixi run -e wasm-build emmake make -C wasm-build
PREFIX=$(pixi info -e wasm-host --json | python3 -c "import sys,json; print(json.load(sys.stdin)['environments_info'][0]['prefix'])")
cmake --install wasm-build --prefix "$PREFIX"

# Build and serve JupyterLite
mkdir -p notebooks
pixi run -e wasm-build jupyter lite build \
  --XeusAddon.prefix="$PREFIX" \
  "--XeusAddon.default_channels=[https://conda.anaconda.org/conda-forge]" \
  --contents notebooks \
  --output-dir _output

# Serve locally
python3 -m http.server 8000 --directory _output
```

Then open http://localhost:8000 in your browser.

### Manual Deployment

If you prefer to deploy manually:

```bash
# Build the site
make deploy

# The output will be in _output/ directory
# You can then deploy this directory to any static hosting service
```

## Development with Nix

The `shell.nix` file provides a development environment with all necessary dependencies:

```bash
nix-shell

# Now you have access to:
# - cmake, pkg-config
# - elan (Lean 4 toolchain manager)
# - Python 3.11 with Jupyter, NumPy, etc.
# - Node.js 23 (required for WASM Memory64 support)
# - emscripten
# - Build tools (clang, libc++, etc.)
```

## CI/CD Pipeline

The GitHub Actions workflow builds and tests on every push:

1. **Native Build** (`native-build` job):
   - Builds the native Linux x86_64 kernel
   - Uploads the `xlean` binary as an artifact

2. **WASM Build** (`wasm-build` job):
   - Sets up emscripten via pixi
   - Builds the WASM kernel with Memory64 support
   - Runs tests with Node.js 23
   - Builds the JupyterLite site
   - Uploads the site for Pages deployment

3. **Deploy Pages** (`deploy-pages` job):
   - Runs only on `main` branch pushes
   - Deploys the artifact to GitHub Pages
   - Requires proper repository settings (see above)
