import Lake
open Lake DSL System

package «xeus-lean» where
  -- add package configuration options here

lean_lib REPL where
  srcDir := "src"

lean_lib ReplFFI where
  srcDir := "src"

-- CommBus is the kernel-side comm session registry. Both Display
-- (which registers comm handlers, e.g. for live waveform viewers) and
-- XeusKernel (which dispatches incoming comm events) depend on it; it
-- lives in its own lib so neither has to import the other.
lean_lib CommBus where
  srcDir := "src"

-- Display.lean provides the #html / #latex / #md / #svg rich-display
-- commands. It is declared as its own lib so that `import Display` from
-- WasmRepl.lean (and user cells) resolves to src/Display.lean.
lean_lib Display where
  srcDir := "src"

lean_lib WasmRepl where
  srcDir := "src"

lean_exe repl where
  root := `REPL.Main
  supportInterpreter := true

lean_exe testmain where
  root := `TestMain
  srcDir := "src"

-- `Convert` lib + `xlean-convert` CLI: convert Markdown chapters
-- (with fenced ```lean code blocks) into Jupyter `.ipynb`
-- notebooks or jupytext-style `.lean:percent` source.  Lets
-- authors keep tutorial chapters in plain Markdown (reviewable,
-- Git-diff-friendly) and generate the runnable artefacts.
lean_lib Convert where
  srcDir := "src"

lean_exe «xlean-convert» where
  root := `ConvertMain
  srcDir := "src"
  supportInterpreter := true

lean_exe «convert-test» where
  root := `ConvertTest
  srcDir := "src"
  supportInterpreter := true

/--
Read `XEUS_LEAN_EXTRA_LIBS` from the process environment at lakefile-load
time. Whitespace-separated tokens, each appended verbatim to xlean's link
line. This is a generic extension point: any library that needs to thread
its own `@[extern]` symbols into the xlean kernel (so user notebook cells
can call them via `#eval`) can build a static `.a` and put its path in
this env var before `lake build xlean`. The xeus-lean lakefile itself
stays free of project-specific deps.

Example (Sparkle):
  XEUS_LEAN_EXTRA_LIBS="/p/libsparkle_olean.a /p/libsparkle_barrier.a" \
    lake build xlean

We use `unsafeBaseIO` because Lake disallows `initialize ← ...` in the
same module that consumes the result, and `moreLinkArgs` is pure
`Array String`. Reading an env var has no observable side effect on the
build, so the unsafe escape is appropriate here. The `@[implemented_by]`
trick lets the compiler treat the definition as a black-box constant
while the runtime actually performs the env read.
-/
unsafe def xleanExtraLinkArgsImpl : Array String := unsafeBaseIO do
  match ← IO.getEnv "XEUS_LEAN_EXTRA_LIBS" with
  | none => pure #[]
  | some v => pure (v.splitOn " " |>.toArray |>.filter (· ≠ ""))

@[implemented_by xleanExtraLinkArgsImpl]
opaque xleanExtraLinkArgs : Array String

@[default_target]
lean_exe xlean where
  root := `XeusKernel
  supportInterpreter := true
  srcDir := "src"
  -- Link with the xeus FFI static library built by cmake.
  -- Platform-specific link arguments. Anything in `XEUS_LEAN_EXTRA_LIBS`
  -- (a whitespace-separated list of paths) is appended verbatim — see
  -- the `xleanExtraLinkArgs` initializer above for the rationale.
  moreLinkArgs := (
    if System.Platform.isWindows then
      #["./build-cmake/libxeus_ffi.a",
        "-L./build-cmake/_deps/xeus-build",
        "-L./build-cmake/_deps/xeus-zmq-build",
        "-lxeus", "-lxeus-zmq", "-lstdc++"]
    else if System.Platform.isOSX then
      #["./build-cmake/libxeus_ffi.a",
        "-L./build-cmake/_deps/xeus-build",
        "-L./build-cmake/_deps/xeus-zmq-build",
        "-Wl,-rpath,@executable_path/../../../build-cmake/_deps/xeus-build",
        "-Wl,-rpath,@executable_path/../../../build-cmake/_deps/xeus-zmq-build",
        "-lxeus", "-lxeus-zmq", "-lstdc++"]
    else  -- Linux
      -- FFI library must be built with leanc (Lean's clang/libc++) for ABI
      -- compatibility. Lean's linker uses its own sysroot and libc++, so
      -- libstdc++ and GCC runtime are not needed.
      -- All deps built from source via FetchContent; do NOT add system lib
      -- paths like -L/usr/lib/x86_64-linux-gnu because leanc uses --sysroot
      -- with its own bundled glibc, and system glibc conflicts (__libc_csu_init).
      -- glibc_isoc23_compat.o provides __isoc23_strtoull etc. shims: system
      -- clang++ compiles against glibc 2.38+ which redirects strtoull→C23
      -- variants, but leanc's older glibc lacks them.
      #["-L./build-cmake/_deps/xeus-build",
        "-L./build-cmake/_deps/xeus-zmq-build",
        "-L./build-cmake/_deps/libzmq-build/lib",
        "-Wl,--start-group",
        "./build-cmake/libxeus_ffi.a",
        "./build-cmake/glibc_isoc23_compat.o",
        "-lxeus", "-lxeus-zmq", "-lzmq",
        "-Wl,--end-group",
        "-lpthread", "-lm", "-ldl"]
  ) ++ xleanExtraLinkArgs

/-- Script to build xlean via cmake -/
script buildXlean do
  -- First build the Lean libraries
  IO.println "Building Lean libraries..."
  let lakeResult ← IO.Process.output {
    cmd := "lake"
    args := #["build", "REPL"]
  }

  if lakeResult.exitCode != 0 then
    IO.eprint lakeResult.stderr
    throw <| IO.userError "Failed to build Lean libraries"

  let buildDir := "build-cmake"

  -- Create build directory if it doesn't exist
  let buildPath : FilePath := buildDir
  if !(← buildPath.pathExists) then
    IO.FS.createDirAll buildDir

  -- Run cmake configure to build C++ FFI library
  IO.println "Configuring CMake to build C++ FFI library..."
  let configResult ← IO.Process.output {
    cmd := "cmake"
    args := #["-S", ".", "-B", buildDir, "-DXEUS_LEAN_BUILD_FFI_ONLY=ON"]
  }

  if configResult.exitCode != 0 then
    IO.eprint configResult.stderr
    throw <| IO.userError "CMake configuration failed"

  -- Build the C++ FFI library
  IO.println "Building C++ FFI library..."
  let buildResult ← IO.Process.output {
    cmd := "cmake"
    args := #["--build", buildDir, "--target", "xeus_ffi"]
  }

  if buildResult.exitCode != 0 then
    IO.eprint buildResult.stderr
    throw <| IO.userError "CMake build of FFI library failed"

  -- Now build the Lean executable that links with the FFI library
  IO.println "Building xlean executable (Lean + FFI)..."
  let xleanResult ← IO.Process.output {
    cmd := "lake"
    args := #["build", "xlean"]
  }

  if xleanResult.exitCode != 0 then
    IO.eprint xleanResult.stderr
    throw <| IO.userError "Failed to build xlean executable"

  IO.println "xlean built successfully at .lake/build/bin/xlean"
  return 0

/-- Script to install xlean kernel to Jupyter -/
script installKernel do
  -- Build first
  let _ ← buildXlean []

  -- Copy kernel spec to Jupyter
  let homeDir ← IO.getEnv "HOME"
  let jupyterDir := homeDir.getD "~" ++ "/Library/Jupyter/kernels/xlean"
  IO.FS.createDirAll jupyterDir

  let currentDir ← IO.currentDir

  -- Create kernel.json content
  let kernelJson :=
    "{" ++ "\n" ++
    "  \"display_name\": \"Lean 4\"," ++ "\n" ++
    "  \"argv\": [" ++ "\n" ++
    s!"    \"{currentDir}/.lake/build/bin/xlean\"," ++ "\n" ++
    "    \"{connection_file}\"" ++ "\n" ++
    "  ]," ++ "\n" ++
    "  \"language\": \"lean\"," ++ "\n" ++
    "  \"interrupt_mode\": \"signal\"," ++ "\n" ++
    "  \"env\": {}" ++ "\n" ++
    "}"

  -- Write kernel.json
  IO.FS.writeFile (jupyterDir ++ "/kernel.json") kernelJson

  IO.println s!"Installed xlean kernel to {jupyterDir}"
  return 0
