{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  name = "xeus-lean-dev-shell";

  # Packages to install in the environment
  buildInputs = with pkgs; [
    pkg-config
    cmake
    elan
    (python3.withPackages (ps: with ps; [
      numpy
      matplotlib
      pyyaml
      pandas
      pip
      jupyter
      jupyterlab
    ]))
    nodejs
    emscripten
    # Additional build dependencies
    nlohmann_json
    libuuid
    openssl
    clang
    libcxx
    libcxxrt
  ];

  # Environment variables
  shellHook = ''
    export CMAKE_C_COMPILER=clang
    export CMAKE_CXX_COMPILER=clang++
    export CMAKE_CXX_FLAGS="-stdlib=libc++"
    echo "xeus-lean development environment loaded"
    echo "Lean toolchain: $(lean --version 2>/dev/null || echo 'run: curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | sh')"
  '';
}
