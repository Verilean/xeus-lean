/-
Copyright (c) 2025, xeus-lean contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Init
import Lean.Data.Json

/-!
# CommBus — kernel-side comm session registry

The xlean kernel exposes a generic Jupyter `comm` channel (target
name `xlean`) so that JS frontends embedded in cell output can talk
back to Lean code over `iopub` without going through `execute_request`.

Each user-facing module (currently `Display.WaveformSession`) registers
a *session* by name. When a JS comm opens with `data.session = "<name>"`,
the kernel binds that session's handler to the comm id; subsequent
`comm_msg` payloads are routed to the handler and its return value is
shipped back over the same comm.

The registry lives in this stand-alone module so both `Display` (which
registers handlers) and `XeusKernel` (which dispatches them) can import
it without a cycle.
-/

namespace CommBus

/-- Handler invoked for each `comm_msg`: receives the parsed `data`,
    returns the JSON to send back over the same comm. -/
abbrev Handler := Lean.Json → IO Lean.Json

/-- Sessions registered by user code, keyed by the string the JS
    frontend names in its `comm_open` `data.session` field. -/
initialize sessions : IO.Ref (Std.HashMap String Handler) ← IO.mkRef {}

/-- Active comms (one per JS frontend instance), keyed by the comm id
    that xeus assigned at open time. Populated by the dispatcher when
    a `comm_open` arrives carrying a known session name; cleared on
    `comm_close`. -/
initialize bindings : IO.Ref (Std.HashMap String Handler) ← IO.mkRef {}

/-- Public registration entry point. Idempotent — re-registering a
    session replaces its previous handler. -/
def register (sessionId : String) (handler : Handler) : IO Unit :=
  sessions.modify (·.insert sessionId handler)

/-- Bind a handler (looked up by session name) to a freshly opened
    comm id. Returns true if the session existed. Used by XeusKernel's
    comm dispatcher; user code shouldn't call this directly. -/
def bindOnOpen (sessionId commId : String) : IO Bool := do
  let s ← sessions.get
  match s[sessionId]? with
  | none => pure false
  | some h => bindings.modify (·.insert commId h); pure true

/-- Look up the handler bound to a comm id, or `none` if no comm with
    that id is open. Used by XeusKernel on `comm_msg`. -/
def lookup (commId : String) : IO (Option Handler) := do
  let b ← bindings.get
  pure b[commId]?

/-- Remove a comm binding when its `comm_close` arrives. -/
def unbind (commId : String) : IO Unit :=
  bindings.modify (·.erase commId)

end CommBus
