/-
Copyright (c) 2025, xeus-lean contributors
Released under Apache 2.0 license as described in the file LICENSE.

Xeus Kernel - Lean owns the main loop and calls C++ xeus via FFI
-/
import REPL.Main
import Lean.Data.Json

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

        -- Format output: show clean output for info, full details for errors
        let formattedJson :=
          if response.messages.isEmpty then
            -- No messages, just return empty string
            ""
          else
            -- Check if all messages are info (not errors/warnings)
            let hasErrors := response.messages.any (fun m =>
              match m.severity with
              | .info => false
              | _ => true)
            if hasErrors then
              -- Show full JSON for errors
              Lean.toJson response |>.compress
            else
              -- For info only, show just the data concatenated
              let outputs := response.messages.map (fun m => m.data)
              String.intercalate "\n" outputs

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
