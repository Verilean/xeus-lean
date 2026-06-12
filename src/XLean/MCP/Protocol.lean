/-
  MCP/Protocol — Model Context Protocol JSON-RPC 2.0 over stdio.

  Reference:
    https://spec.modelcontextprotocol.io/

  Wire format on the stdio transport (which is what Claude Code and
  most MCP hosts use):

    Content-Length: <N>\r\n
    \r\n
    <JSON payload of length N>

  Each JSON payload is a JSON-RPC 2.0 message:
    { "jsonrpc": "2.0", "id": …, "method": "...", "params": {...} }

  The server (us) reads a stream of these from stdin, dispatches by
  `method`, and writes a single response back to stdout for each
  request — also in the Content-Length-framed form.  Notifications
  (no `id`) get no response.

  This file is the *transport + dispatch* layer; it doesn't know
  about any particular Lean operation.  Tool handlers register
  themselves with a `Server` and the dispatcher calls them by name.
-/

import Lean.Data.Json
import Lean.Data.Json.Parser

namespace XLean.MCP

open Lean (Json ToJson FromJson)

/-- A JSON-RPC 2.0 request as we receive it on stdin. -/
structure Request where
  id     : Option Json := none  -- null / number / string; absent for notifications
  method : String
  params : Json := Json.null
  deriving Inhabited

/-- A JSON-RPC 2.0 response we write back to stdout.  Either `result`
    or `error`, not both. -/
structure Response where
  id      : Json := Json.null
  result  : Option Json := none
  error   : Option (Int × String) := none

/-- Render a Response as the JSON-RPC envelope. -/
def Response.toJson (r : Response) : Json :=
  let base : List (String × Json) := [("jsonrpc", "2.0"), ("id", r.id)]
  match r.result, r.error with
  | some v, _ => Json.mkObj (base ++ [("result", v)])
  | _, some (code, msg) =>
      Json.mkObj (base ++ [("error", Json.mkObj [("code", code), ("message", msg)])])
  | none, none =>
      -- Shouldn't happen; respond with a null result.
      Json.mkObj (base ++ [("result", Json.null)])

/-- A handler takes JSON params and returns either a JSON result or a
    `(code, message)` JSON-RPC error.  Lives in IO so handlers can
    touch the world (Lean session env, FS, etc.). -/
abbrev Handler := Json → IO (Except (Int × String) Json)

/-- One tool's catalogue entry.  Lives in Protocol so the tool-
    implementation modules (FileTools, NotebookTools, …) can build
    ToolInfo values without depending on Tools.lean. -/
structure ToolInfo where
  name        : String
  description : String
  /-- JSON Schema for the tool's arguments object.  Raw `Json` so we
      don't need to mirror schema vocabulary in Lean types. -/
  inputSchema : Json

/-- Encode `ToolInfo` in the shape `tools/list` expects. -/
def ToolInfo.toJson (t : ToolInfo) : Json :=
  Json.mkObj
    [ ("name",        t.name)
    , ("description", t.description)
    , ("inputSchema", t.inputSchema)
    ]

/-- MCP wraps a tool's payload in
    `{ "content": [ { "type": "text", "text": "..." } ] }`; this is
    the shape Claude Code expects to display in chat. -/
def textContent (s : String) : Json :=
  Json.mkObj
    [ ("content", Json.arr #[
        Json.mkObj [("type", "text"), ("text", s)]
      ])
    ]

/-- The server is a registry of method name → handler. -/
structure Server where
  handlers : Std.HashMap String Handler := {}

namespace Server

/-- Register a method handler. -/
def addHandler (s : Server) (name : String) (h : Handler) : Server :=
  { s with handlers := s.handlers.insert name h }

/-- Look up a handler. -/
def lookup (s : Server) (name : String) : Option Handler :=
  s.handlers.get? name

end Server

-- --------------------------------------------------------------------------
-- Transport: newline-delimited JSON over stdio.
--
-- The MCP stdio transport spec is one JSON-RPC message per line, NOT
-- LSP's `Content-Length:`-framed form.  Hosts (Claude Code, Cursor, the
-- official TS/Python SDKs) all send `{...}\n` and then wait for a
-- `{...}\n` reply; an LSP-style server hangs forever on the missing
-- header and the host times out at ~30 s.  See
-- https://spec.modelcontextprotocol.io/specification/basic/transports/#stdio.
-- --------------------------------------------------------------------------

/-- Read one newline-delimited JSON message from `h`.  Returns `none` at
    EOF (or on a parse error — host can resync by sending the next
    message).  Blank lines are tolerated and skipped. -/
partial def readMessage (h : IO.FS.Stream) : IO (Option Json) := do
  let rec loop : IO (Option Json) := do
    let line ← h.getLine
    if line.isEmpty then
      -- EOF.
      return none
    let trimmed := line.trim
    if trimmed.isEmpty then
      -- Empty / whitespace-only line — keep reading.
      loop
    else
      match Json.parse trimmed with
      | .ok j    => return some j
      | .error _ => return none
  loop

/-- Write a JSON message as a single line terminated by `\n`.
    `Json.compress` already strips internal whitespace, so the body is
    safe to concatenate with `\n` without further escaping. -/
def writeMessage (h : IO.FS.Stream) (j : Json) : IO Unit := do
  let body := j.compress ++ "\n"
  h.write body.toUTF8
  h.flush

-- --------------------------------------------------------------------------
-- Dispatch.
-- --------------------------------------------------------------------------

/-- Parse a single message; if it's a request, dispatch and write the
    response.  Notifications (no `id`) are dispatched for side
    effects but produce no response. -/
def handleMessage (s : Server) (msg : Json) : IO (Option Response) := do
  let method := msg.getObjValAs? String "method" |>.toOption.getD ""
  let id     := msg.getObjVal?     "id"          |>.toOption.getD Json.null
  let params := msg.getObjVal?     "params"      |>.toOption.getD Json.null
  let isReq  := !id.isNull
  match s.lookup method with
  | none =>
    if isReq then
      pure (some { id := id, error := some (-32601, s!"Method not found: {method}") })
    else
      pure none
  | some h =>
    match ← h params with
    | .ok j    =>
      if isReq then pure (some { id := id, result := some j }) else pure none
    | .error (code, msg) =>
      if isReq then pure (some { id := id, error := some (code, msg) }) else pure none

/-- Top-level event loop: read messages until EOF, dispatching each. -/
partial def runStdio (s : Server) : IO Unit := do
  let inH  ← IO.getStdin
  let outH ← IO.getStdout
  let rec loop : IO Unit := do
    match ← readMessage inH with
    | none => return ()  -- EOF, exit cleanly
    | some msg =>
      try
        if let some resp ← handleMessage s msg then
          writeMessage outH (Response.toJson resp)
      catch e =>
        -- An exception inside a handler shouldn't crash the server;
        -- surface it back as an internal-error response if it was a
        -- request, otherwise log to stderr.
        let id := msg.getObjVal? "id" |>.toOption.getD Json.null
        if !id.isNull then
          let resp : Response :=
            { id := id, error := some (-32603, s!"Internal error: {e.toString}") }
          writeMessage outH (Response.toJson resp)
        else
          IO.eprintln s!"[MCP] notification handler threw: {e.toString}"
      loop
  loop

end XLean.MCP
