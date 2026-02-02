#!/bin/bash
# Build script for xeus-lean

set -e  # Exit on error

echo "Building xeus-lean..."
echo "===================="

# Step 1: Build Lean REPL if needed
if [ ! -f "repl/.lake/build/bin/repl" ]; then
    echo "Building Lean REPL..."
    cd repl
    lake build
    cd ..
    echo "✓ Lean REPL built"
else
    echo "✓ Lean REPL already built"
fi

# Step 2: Create build directory
if [ ! -d "build" ]; then
    mkdir build
    echo "✓ Created build directory"
fi

# Step 3: Configure with CMake
echo "Configuring with CMake..."
cd build
cmake .. "$@"
echo "✓ Configuration complete"

# Step 4: Build
echo "Building xeus-lean..."
cmake --build . -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
echo "✓ Build complete"

# Step 5: Show next steps
echo ""
echo "===================="
echo "Build successful!"
echo ""
echo "To install:"
echo "  cd build && sudo cmake --install ."
echo ""
echo "To test:"
echo "  ./build/xlean --help"
echo ""
echo "After install, verify kernel:"
echo "  jupyter kernelspec list"
