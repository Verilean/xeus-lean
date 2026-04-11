/-
Sparkle HDL demo for xeus-lean Jupyter kernel.

This file verifies that Sparkle can be imported and basic circuit
definition + simulation works. It serves as both a build-test and
a reference for notebook cells.
-/
import Sparkle

open Sparkle.Core.Domain
open Sparkle.Core.Signal

-- A simple 4-bit counter that increments every clock cycle.
def counter4 : Signal defaultDomain (BitVec 4) :=
  Signal.circuit do
    let count ← Signal.reg 0#4;
    count <~ count + 1#4;
    return count

-- Simulation runs at runtime (not #eval at build time) because
-- Sparkle's Signal.evalSignalAt uses C FFI that requires the
-- native shared library to be loaded.
def main : IO Unit := do
  let results := counter4.sample 20
  IO.println s!"4-bit counter (20 cycles): {results}"
