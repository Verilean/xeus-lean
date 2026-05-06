/-
Copyright (c) 2025, xeus-lean contributors
Released under Apache 2.0 license as described in the file LICENSE.

Xeus Kernel - Lean owns the main loop and calls C++ xeus via FFI
-/
import REPL.Main
import Lean.Data.Json
-- Display lets user cells emit MIME-typed payloads (HTML / SVG / Markdown / ...).
-- The buffer is drained after every cell and forwarded to Jupyter through the
-- C++ FFI, which parses the MIME markers out of the result string.
import Display
-- Comm dispatcher: shared session registry that Display (and any other
-- module that wants to talk to a JS frontend over iopub) registers
-- handlers in. We pump it once per kernel-loop iteration below.
import CommBus

namespace XeusKernel

open REPL Lean

/-- Check if debug mode is enabled via XLEAN_DEBUG environment variable -/
def isDebugEnabled : IO Bool := do
  let env ← IO.getEnv "XLEAN_DEBUG"
  return env.isSome && (env.get! == "1" || env.get! == "true")

/-- Debug logging - only outputs if XLEAN_DEBUG is set -/
def debugLog (msg : String) : IO Unit := do
  if ← isDebugEnabled then
    IO.eprintln msg

/-- Opaque handle to the C++ xeus kernel (external object managed by Lean's GC) -/
opaque KernelHandle : Type

/-- Initialize the FFI system (must be called before using the kernel) -/
@[extern "xeus_ffi_initialize"]
opaque ffiInitialize : IO Unit

/-- Create and initialize xeus kernel from connection file -/
@[extern "xeus_kernel_init"]
opaque kernelInit (connectionFile : @& String) : IO (Option KernelHandle)

/-- Poll for messages from Jupyter (returns JSON or empty string if no message) -/
@[extern "xeus_kernel_poll"]
opaque kernelPoll (handle : @& KernelHandle) (timeoutMs : UInt32) : IO String

/-- Send execution result back to Jupyter -/
@[extern "xeus_kernel_send_result"]
opaque kernelSendResult (handle : @& KernelHandle) (executionCount : UInt32) (result : @& String) : IO Unit

/-- Send execution error back to Jupyter -/
@[extern "xeus_kernel_send_error"]
opaque kernelSendError (handle : @& KernelHandle) (executionCount : UInt32) (error : @& String) : IO Unit

/-- Check if kernel should shutdown -/
@[extern "xeus_kernel_should_stop"]
opaque kernelShouldStop (handle : @& KernelHandle) : IO Bool

/-- Pop one queued comm event (open/msg/close) as JSON, "" if none. -/
@[extern "xeus_kernel_poll_comm"]
opaque kernelPollComm (handle : @& KernelHandle) : IO String

/-- Send a JSON message back to the JS side over the comm `commId`.
    Returns true on success, false if the comm has been closed. -/
@[extern "xeus_kernel_send_comm"]
opaque kernelSendComm (handle : @& KernelHandle) (commId : @& String) (data : @& String) : IO Bool

/-- Process a single comm event JSON. -/
private def processOneCommEvent (handle : KernelHandle) (ev : String) : IO Unit := do
  match Lean.Json.parse ev with
  | .error e => IO.eprintln s!"[Lean Kernel] comm event parse error: {e}"
  | .ok j =>
    let op := j.getObjValAs? String "op" |>.toOption.getD ""
    let id := j.getObjValAs? String "id" |>.toOption.getD ""
    match op with
    | "open" =>
      -- JS frontend names which Lean session it wants in data.session.
      let data := j.getObjVal? "data" |>.toOption.getD .null
      let session := data.getObjValAs? String "session" |>.toOption.getD ""
      let bound ← CommBus.bindOnOpen session id
      if bound then
        IO.eprintln s!"[Lean Kernel] comm open session={session} id={id}"
      else
        IO.eprintln s!"[Lean Kernel] comm open for unknown session={session} id={id}"
    | "msg" =>
      let data := j.getObjVal? "data" |>.toOption.getD .null
      match ← CommBus.lookup id with
      | none => IO.eprintln s!"[Lean Kernel] comm msg for unknown id={id}"
      | some h =>
        try
          let reply ← h data
          let _ ← kernelSendComm handle id reply.compress
        catch e =>
          IO.eprintln s!"[Lean Kernel] comm handler raised: {e.toString}"
    | "close" =>
      CommBus.unbind id
    | _ =>
      IO.eprintln s!"[Lean Kernel] unknown comm op: {op}"

/-- Drain the C++ comm event queue and dispatch each entry. Called once
    per poll-loop iteration so comm traffic is interleaved with
    execute_request handling at the same ~100 ms cadence. -/
partial def drainCommEvents (handle : KernelHandle) : IO Unit := do
  let ev ← kernelPollComm handle
  if ev.isEmpty then return
  processOneCommEvent handle ev
  drainCommEvents handle

/-- Message types from Jupyter -/
inductive MessageType
  | executeRequest (code : String) (executionCount : UInt32)
  | shutdownRequest
  | unknown
  deriving Inhabited

/-- Parse message JSON from xeus -/
def parseMessage (json : String) : IO MessageType := do
  if json.isEmpty then
    return .unknown

  let parsed := Json.parse json
  match parsed with
  | .error _ => return .unknown
  | .ok j =>
    match j.getObjVal? "msg_type" with
    | .error _ => return .unknown
    | .ok msgType =>
      let msgTypeStr := msgType.getStr?.toOption.getD ""

      if msgTypeStr == "execute_request" then
        match j.getObjVal? "content" with
        | .ok content =>
          let code := content.getObjVal? "code" |>.toOption.bind (·.getStr?.toOption) |>.getD ""
          let execCount := content.getObjVal? "execution_count" |>.toOption.bind (·.getNat?.toOption) |>.getD 0
          return .executeRequest code execCount.toUInt32
        | .error _ => return .unknown
      else if msgTypeStr == "shutdown_request" then
        return .shutdownRequest
      else
        return .unknown

/-- Main kernel loop with environment tracking -/
partial def kernelLoop (handle : KernelHandle) (replState : IO.Ref State) (currentEnv : Option Nat) : IO Unit := do
  -- Pump any pending comm events first; they're independent of execute
  -- requests and arrive on iopub, so leaving them in the queue would
  -- delay JS frontends until the next user-driven cell.
  drainCommEvents handle

  -- Poll for messages with 100ms timeout
  let msgJson ← kernelPoll handle 100

  if msgJson.isEmpty then
    -- No message, check if we should stop
    let shouldStop ← kernelShouldStop handle
    if shouldStop then
      return ()
    else
      kernelLoop handle replState currentEnv
  else
    -- Process message
    let msgType ← parseMessage msgJson

    match msgType with
    | .executeRequest code execCount =>
      debugLog s!"[Lean Kernel] Executing: {code} (env: {currentEnv})"

      -- Run command through REPL, using the current environment
      let cmd : REPL.Command := {
        cmd := code,
        env := currentEnv,  -- Use current environment to persist definitions
        infotree := none,
        allTactics := none,
        rootGoals := none
      }
      let state ← replState.get
      let result ← runCommand cmd |>.run state

      match result with
      | (.inl response, newState) =>
        replState.set newState

        -- Format messages for the notebook. We render every severity
        -- (info, warning, error) the same way Lean's compiler does:
        --   <line>:<col>: <severity>: <data>
        -- so users see a compact, scannable trace instead of a JSON dump.
        let renderMsg (m : REPL.Message) : String :=
          let sev := match m.severity with
            | .info    => "info"
            | .warning => "warning"
            | .error   => "error"
            | .trace   => "trace"
          let posStr := s!"{m.pos.line}:{m.pos.column}"
          if sev == "info" then
            -- Plain `#eval` / `#check` output: don't prepend a position
            -- prefix, just show the data — matches what users expect from
            -- a REPL.
            m.data
          else
            s!"{posStr}: {sev}: {m.data}"
        let renderedMsgs :=
          if response.messages.isEmpty then ""
          else String.intercalate "\n" (response.messages.map renderMsg)

        -- Drain any MIME-typed payloads (Display.html / .svg / .waveform / ...)
        -- that the cell deposited in the global Display buffer. C++ parses
        -- the markers (`\x1bMIME:<type>\x1e<payload>\x1b/MIME\x1e`) and routes
        -- each one to the correct Jupyter mime bundle key.
        let displayOutput ← Display.drain
        let formattedJson :=
          if displayOutput.isEmpty then renderedMsgs
          else if renderedMsgs.isEmpty then displayOutput
          else renderedMsgs ++ "\n" ++ displayOutput

        kernelSendResult handle execCount formattedJson

        debugLog s!"[Lean Kernel] Success (env: {response.env})"

        -- Continue with the new environment ID
        kernelLoop handle replState (some response.env)

      | (.inr error, newState) =>
        replState.set newState

        -- Send error back to Jupyter
        let errorJson := Lean.toJson error |>.compress
        kernelSendError handle execCount errorJson

        debugLog s!"[Lean Kernel] Error: {errorJson}"

        -- Keep the same environment on error
        kernelLoop handle replState currentEnv

    | .shutdownRequest =>
      debugLog "[Lean Kernel] Shutdown requested"
      return ()

    | .unknown =>
      debugLog s!"[Lean Kernel] Unknown message: {msgJson}"
      kernelLoop handle replState currentEnv

end XeusKernel

open XeusKernel

/-- Main entry point -/
def main (args : List String) : IO Unit := do
  -- Get connection file from arguments
  let connectionFile := match args with
    | f :: _ => f
    | [] => "connection.json"

  debugLog s!"[Lean Kernel] Starting with connection file: {connectionFile}"

  -- Initialize search path
  Lean.initSearchPath (← Lean.findSysroot)

  debugLog "[Lean Kernel] Initializing FFI..."
  ffiInitialize

  debugLog "[Lean Kernel] Initializing xeus kernel..."

  -- Initialize xeus kernel
  match ← kernelInit connectionFile with
  | none =>
    IO.eprintln "[Lean Kernel] Failed to initialize xeus kernel"
    throw (IO.userError "Kernel initialization failed")

  | some handle =>
    debugLog "[Lean Kernel] Xeus kernel initialized successfully"

    -- Initialize REPL state
    let initialState : REPL.State := { cmdStates := #[], proofStates := #[] }
    let replState ← IO.mkRef initialState

    debugLog "[Lean Kernel] Starting kernel event loop..."

    -- Run kernel loop with initial empty environment
    kernelLoop handle replState none

    debugLog "[Lean Kernel] Kernel stopped"
