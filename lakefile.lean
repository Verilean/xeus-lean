import Lake
open Lake DSL System

package «xeus-lean» where
  -- add package configuration options here

lean_lib REPL where
  srcDir := "src"

lean_lib ReplFFI where
  srcDir := "src"

lean_lib WasmRepl where
  srcDir := "src"

lean_exe repl where
  root := `REPL.Main
  supportInterpreter := true

lean_exe testmain where
  root := `TestMain
  srcDir := "src"

@[default_target]
lean_exe xlean where
  root := `XeusKernel
  supportInterpreter := true
  srcDir := "src"
  -- Link with the xeus FFI static library built by cmake
  -- Platform-specific link arguments
  moreLinkArgs :=
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
      #["-Wl,--start-group",
        "./build-cmake/libxeus_ffi.a",
        "-L./build-cmake/_deps/xeus-build",
        "-L./build-cmake/_deps/xeus-zmq-build",
        "-lxeus", "-lxeus-zmq",
        "-Wl,--end-group",
        "-L/usr/lib/gcc/x86_64-linux-gnu/13",
        "-L/usr/lib/x86_64-linux-gnu",
        "-lstdc++", "-lgcc_s", "-lpthread", "-lm", "-ldl"]

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
