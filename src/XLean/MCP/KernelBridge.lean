/-
  XLean.MCP.KernelBridge — Talk to the running Jupyter kernel.

  Glues the REST surface (`HTTP`) and the channels WebSocket (`WS`)
  to expose one operation: send a Lean snippet to the live
  `xeus-lean` kernel and collect the cell outputs (text, MIME
  bundles, errors).

  This is the heart of the `kernel_execute` MCP tool — the thing
  that lets an MCP host drive the same kernel the user is staring
  at in their browser, with full env continuity (no fresh-process
  semantics like `lean_eval` has today).

  Tested against Jupyter Server in the sparkle tutorial Docker
  image (`MultiKernelManager.default_kernel_name=xeus-lean`,
  `ServerApp.token=""`).  TLS, token auth, and HTTP/2 are out of
  scope.
-/
import XLean.MCP.Net.HTTP
import XLean.MCP.Net.WS
import Lean.Data.Json

namespace XLean.MCP.KernelBridge

open Lean (Json)
open XLean.MCP.Net

/-- Hardcoded Jupyter Server endpoint. -/
def jupyterPort : UInt16 := 8888
def jupyterHost : String := "localhost"

/-- Pseudo-UUID v4.  We don't need cryptographic randomness — the
    field is only used as a correlation id between the
    `execute_request` we send and the messages we receive back.
    Time-based bytes are plenty unique per call. -/
private def newId : IO String := do
  let t ← IO.monoNanosNow
  let r ← IO.rand 0 0xFFFFFFFF
  let hex (n : Nat) (w : Nat) : String := Id.run do
    let mut s := ""
    let mut x := n
    for _ in [0:w] do
      let d := x &&& 0xF
      s := (if d < 10 then Char.ofNat (d + 48) else Char.ofNat (d - 10 + 97)).toString ++ s
      x := x >>> 4
    pure s
  -- 8-4-4-4-12 hex layout.  Version / variant bits are not set;
  -- nothing in the Jupyter protocol enforces them.
  pure s!"{hex t 8}-{hex (t >>> 32) 4}-{hex r 4}-{hex (r >>> 16) 4}-{hex t 12}"

/-- Build the JSON wire form of an `execute_request`. -/
private def mkExecuteRequest (sessionId msgId code : String) : Json :=
  Json.mkObj
    [ ("header", Json.mkObj
        [ ("msg_id",   msgId)
        , ("username", "xlean-mcp")
        , ("session",  sessionId)
        , ("date",     "1970-01-01T00:00:00Z")  -- nominal; server doesn't enforce
        , ("msg_type", "execute_request")
        , ("version",  "5.3")
        ])
    , ("parent_header", Json.mkObj [])
    , ("metadata",      Json.mkObj [])
    , ("content", Json.mkObj
        [ ("code",             code)
        , ("silent",           false)
        , ("store_history",    true)
        , ("user_expressions", Json.mkObj [])
        , ("allow_stdin",      false)
        , ("stop_on_error",    true)
        ])
    , ("buffers", Json.arr #[])
    , ("channel", "shell")
    ]

/-- One output payload collected from the kernel's iopub channel. -/
inductive Output where
  | stream  (name : String) (text : String)                  -- stdout / stderr
  | mime    (data : Lean.Json)                                 -- display_data / execute_result
  | error   (ename : String) (evalue : String) (traceback : Array String)
  deriving Inhabited

/-- Render one `Output` as a single JSON object.  The shape mirrors
    Jupyter's own output schema so MCP clients can pattern-match. -/
def Output.toJson : Output → Json
  | .stream name text =>
    Json.mkObj [("output_type", "stream"), ("name", name), ("text", text)]
  | .mime data =>
    Json.mkObj [("output_type", "display_data"), ("data", data)]
  | .error ename evalue tb =>
    Json.mkObj
      [ ("output_type", "error")
      , ("ename",       ename)
      , ("evalue",      evalue)
      , ("traceback",   Json.arr (tb.map Json.str))
      ]

/-- The collected result of one `execute_request`. -/
structure ExecuteResult where
  status       : String                  -- "ok" / "error"
  outputs      : Array Output := #[]

/-- Find a live `xeus-lean` kernel, or start one if none exists.
    Returns the kernel id. -/
def findOrStartKernel : IO String := do
  let r ← HTTP.get jupyterHost jupyterPort "/api/kernels"
  let j ← r.json
  let kernels := j.getArr?.toOption.getD #[]
  let existing := kernels.findSome? fun k =>
    let name := k.getObjValAs? String "name" |>.toOption.getD ""
    let id   := k.getObjValAs? String "id"   |>.toOption.getD ""
    if name == "xeus-lean" then some id else none
  match existing with
  | some id => pure id
  | none =>
    let body := Json.mkObj [("name", "xeus-lean")]
    let r ← HTTP.postJson jupyterHost jupyterPort "/api/kernels" body
    let j ← r.json
    match j.getObjValAs? String "id" with
    | .ok id => pure id
    | .error e => throw (IO.userError s!"start kernel: {e}")

/-- Process one message from iopub, accumulating into the result. -/
private def absorbMessage (res : ExecuteResult) (msg : Json) (myMsgId : String)
    : Bool × ExecuteResult := Id.run do
  let parentId :=
    msg.getObjVal? "parent_header" |>.toOption
       |>.bind (·.getObjVal? "msg_id" |>.toOption)
       |>.bind (·.getStr?.toOption)
       |>.getD ""
  -- Ignore traffic from other clients sharing the kernel.
  if parentId ≠ myMsgId then return (false, res)
  let msgType :=
    msg.getObjVal? "header" |>.toOption
       |>.bind (·.getObjVal? "msg_type" |>.toOption)
       |>.bind (·.getStr?.toOption)
       |>.getD ""
  let content := msg.getObjVal? "content" |>.toOption.getD Json.null
  match msgType with
  | "stream" =>
    let name := content.getObjValAs? String "name" |>.toOption.getD "stdout"
    let text := content.getObjValAs? String "text" |>.toOption.getD ""
    return (false, { res with outputs := res.outputs.push (.stream name text) })
  | "display_data" | "execute_result" =>
    let data := content.getObjVal? "data" |>.toOption.getD (Json.mkObj [])
    return (false, { res with outputs := res.outputs.push (.mime data) })
  | "error" =>
    let ename  := content.getObjValAs? String "ename"  |>.toOption.getD ""
    let evalue := content.getObjValAs? String "evalue" |>.toOption.getD ""
    let tb     := (content.getObjVal? "traceback" |>.toOption.bind (·.getArr?.toOption)).getD #[]
    let tbStrs := tb.map (·.getStr?.toOption.getD "")
    return (false, { res with status := "error",
                              outputs := res.outputs.push (.error ename evalue tbStrs) })
  | "execute_reply" =>
    -- Shell channel acknowledgement.  Update status but keep
    -- reading iopub — execute_result / stream / status:idle can
    -- still arrive after the reply.
    let st := content.getObjValAs? String "status" |>.toOption.getD "ok"
    return (false, { res with status := st })
  | "status" =>
    -- Spec: kernel returns to `idle` once it's finished publishing
    -- everything for this parent request.  That's our real stop
    -- signal.
    let state := content.getObjValAs? String "execution_state" |>.toOption.getD ""
    return (state == "idle", res)
  | _ =>
    -- execute_input and others — don't accumulate.
    return (false, res)

/-- Send `code` to the kernel and collect its outputs.  Times out
    after `maxMessages` iopub messages — a runaway loop in user
    code can't tar-pit the MCP server. -/
partial def execute (code : String) (maxMessages : Nat := 200)
    : IO ExecuteResult := do
  let kernelId ← findOrStartKernel
  let sessionId ← newId
  let msgId     ← newId
  let path := s!"/api/kernels/{kernelId}/channels?session_id={sessionId}"
  let ws ← WS.connect jupyterPort path
  let req := mkExecuteRequest sessionId msgId code
  WS.sendText ws req.compress
  let mut res : ExecuteResult := { status := "ok" }
  let mut remaining := maxMessages
  let mut done := false
  while !done && remaining > 0 do
    remaining := remaining - 1
    match ← WS.recvText ws with
    | none => done := true   -- Close frame
    | some line =>
      match Json.parse line with
      | .error _ => continue   -- Skip undecodeable noise
      | .ok msg =>
        let (stop, res') := absorbMessage res msg msgId
        res := res'
        if stop then done := true
  WS.close ws
  pure res

end XLean.MCP.KernelBridge
