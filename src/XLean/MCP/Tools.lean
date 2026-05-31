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

namespace XLean.MCP

open Lean (Json)

/-- One tool's catalogue entry. -/
structure ToolInfo where
  name        : String
  description : String
  /-- JSON Schema for the tool's arguments object.  Keeping this as a
      raw `Json` so we don't need to mirror the full schema vocabulary
      in Lean types. -/
  inputSchema : Json

/-- Encode `ToolInfo` in the shape `tools/list` expects. -/
def ToolInfo.toJson (t : ToolInfo) : Json :=
  Json.mkObj
    [ ("name",        t.name)
    , ("description", t.description)
    , ("inputSchema", t.inputSchema)
    ]

/-- The top-level tools/call wrapping.  MCP wraps a tool's payload in
    `{ "content": [ { "type": "text", "text": "..." } ] }`; this is
    the shape Claude Code expects to display in chat. -/
def textContent (s : String) : Json :=
  Json.mkObj
    [ ("content", Json.arr #[
        Json.mkObj [("type", "text"), ("text", s)]
      ])
    ]

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

/-- The set of tools we register at server start.  Returned as a list
    so the dispatcher can wire them up + the `tools/list` handler can
    enumerate them. -/
def builtinTools (sess : IO.Ref LeanSession) : List (ToolInfo × Handler) :=
  [ tool_lean_eval sess
    -- More tools will land here:
    -- tool_lean_check sess,
    -- tool_notebook_read,
    -- tool_notebook_edit,
    -- tool_project_search,
    -- tool_file_read,
    -- tool_file_write,
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
