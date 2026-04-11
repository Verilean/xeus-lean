import Lake
open Lake DSL

package «sparkle-demo» where
  leanOptions := #[⟨`autoImplicit, false⟩]

require sparkle from git
  "https://github.com/Verilean/sparkle" @ "main"

@[default_target]
lean_exe sparkleDemo where
  root := `SparkleDemo
  supportInterpreter := true
