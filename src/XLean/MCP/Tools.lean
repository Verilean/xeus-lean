/-
  MCP/Tools — the lifecycle methods and the tool registry.

  MCP exposes operations to the client through two main JSON-RPC
  methods:

    tools/list — return the catalogue of available tools (one entry
                 per registered function, with name + description +
                 JSON-schema for its arguments).
    tools/call — invoke a tool by name with the supplied arguments,
                 return its result.

  This module registers the catalogue once at start-up and the
  dispatcher delegates `tools/call <name>` to the matching handler.

  Tools are intentionally narrow: each does one job, returns one
  structured payload.  Composition is the client's responsibility.
-/

import XLean.MCP.Protocol
import XLean.MCP.LeanSession
import XLean.MCP.FileTools
import XLean.MCP.NotebookTools
import XLean.MCP.KernelBridge

namespace XLean.MCP

open Lean (Json)

-- ToolInfo + textContent live in Protocol.lean so that the tool
-- modules (FileTools, NotebookTools) can use them without a
-- circular import.

-- --------------------------------------------------------------------------
-- Tool definitions
-- --------------------------------------------------------------------------

/-- `lean_eval`: send a Lean snippet to the persistent session and
    return the rendered messages (#eval output, errors, etc.). -/
def tool_lean_eval (sess : IO.Ref LeanSession) : ToolInfo × Handler :=
  let info : ToolInfo :=
    { name := "lean_eval"
      description :=
        "Evaluate a Lean 4 code snippet against the kernel's "
        ++ "persistent environment.  Returns the textual messages "
        ++ "Lean emits (output from #eval, types from #check, errors, "
        ++ "warnings, info traces).  The environment carries across "
        ++ "calls, just like cells in a notebook."
      inputSchema := Json.mkObj
        [ ("type",       "object")
        , ("properties", Json.mkObj
            [ ("code", Json.mkObj
                [ ("type",        "string")
                , ("description", "The Lean code to evaluate.")
                ])
            ])
        , ("required",   Json.arr #["code"])
        ]
    }
  let handler : Handler := fun params => do
    match params.getObjValAs? String "code" with
    | .error _ => return .error (-32602, "Missing required parameter: code")
    | .ok code =>
      let output ← (← sess.get).eval code
      sess.modify (·.advance)  -- placeholder; LeanSession owns its env
      return .ok (textContent output)
  (info, handler)

-- --------------------------------------------------------------------------
-- Lifecycle method handlers (initialize, tools/list, tools/call)
-- --------------------------------------------------------------------------

/-- `kernel_execute`: send a Lean snippet to the *running* xeus-lean
    kernel (the same one the user's notebook is attached to) and
    return the cell outputs.  Unlike `lean_eval` this preserves
    env across calls and emits real MIME outputs (so a cell that
    renders an SVG waveform here will appear in the user's
    browser too). -/
def tool_kernel_execute : ToolInfo × Handler :=
  let info : ToolInfo :=
    { name := "kernel_execute"
      description :=
        "Execute a Lean snippet against the LIVE xeus-lean kernel "
        ++ "running under Jupyter Server on localhost:8888.  Shares "
        ++ "env with the user's notebook session (state persists, "
        ++ "MIME outputs like `image/svg+xml` waveforms appear in "
        ++ "the browser).  Returns a JSON array of Jupyter-shaped "
        ++ "output records (`stream` / `display_data` / `error`)."
      inputSchema := Json.mkObj
        [ ("type",       "object")
        , ("properties", Json.mkObj
            [ ("code", Json.mkObj
                [ ("type",        "string")
                , ("description", "The Lean code to execute.")
                ])
            ])
        , ("required",   Json.arr #["code"])
        ]
    }
  let handler : Handler := fun params => do
    match params.getObjValAs? String "code" with
    | .error _ => return .error (-32602, "Missing required parameter: code")
    | .ok code =>
      try
        let result ← KernelBridge.execute code
        let body := Json.mkObj
          [ ("status",  result.status)
          , ("outputs", Json.arr (result.outputs.map KernelBridge.Output.toJson))
          ]
        return .ok (textContent body.pretty)
      catch e =>
        return .error (-32000, s!"kernel_execute: {e.toString}")
  (info, handler)

/-- The set of tools we register at server start.  Returned as a list
    so the dispatcher can wire them up + the `tools/list` handler can
    enumerate them. -/
def builtinTools (sess : IO.Ref LeanSession) : List (ToolInfo × Handler) :=
  [ tool_lean_eval sess
  , tool_kernel_execute
  , tool_file_read
  , tool_file_write
  , tool_project_search
  , tool_notebook_read
  , tool_notebook_edit
    -- More to come:
    -- tool_lean_check sess,
    -- tool_notebook_evaluate,
    -- tool_lake_build,
    -- tool_lake_test,
  ]

/-- Build a `Server` with the lifecycle + tool methods wired up. -/
def buildServer (sess : IO.Ref LeanSession) : Server := Id.run do
  let tools := builtinTools sess
  let mut s : Server := {}

  -- initialize: handshake.  Return server capabilities + protocol
  -- version.  MCP clients send this first; we just acknowledge.
  s := s.addHandler "initialize" fun _params => do
    pure (.ok (Json.mkObj
      [ ("protocolVersion", "2024-11-05")
      , ("serverInfo", Json.mkObj
          [ ("name",    "xlean-mcp")
          , ("version", "0.1.0")
          ])
      , ("capabilities", Json.mkObj
          [ ("tools", Json.mkObj [])
          ])
      ]))

  -- notifications/initialized: the client acknowledges initialize.
  -- No response expected.
  s := s.addHandler "notifications/initialized" fun _ => pure (.ok Json.null)

  -- tools/list: enumerate the registered tools.
  s := s.addHandler "tools/list" fun _params => do
    let catalogue := tools.map (fun (info, _) => info.toJson)
    pure (.ok (Json.mkObj [("tools", Json.arr catalogue.toArray)]))

  -- tools/call: dispatch to the matching tool handler.
  let lookup : String → Option Handler := fun name =>
    tools.find? (fun (info, _) => info.name == name) |>.map (·.2)
  s := s.addHandler "tools/call" fun params => do
    match params.getObjValAs? String "name" with
    | .error _ => return .error (-32602, "Missing required parameter: name")
    | .ok name =>
      let args := params.getObjVal? "arguments" |>.toOption.getD Json.null
      match lookup name with
      | none   => return .error (-32601, s!"Unknown tool: {name}")
      | some h => h args

  -- shutdown: client asks the server to prepare for exit.
  s := s.addHandler "shutdown" fun _ => pure (.ok Json.null)

  return s

end XLean.MCP
