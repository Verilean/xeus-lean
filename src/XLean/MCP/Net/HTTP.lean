/-
  XLean.MCP.Net.HTTP — Minimal synchronous HTTP/1.1 client.

  Built on Lean's stdlib `Std.Internal.UV.TCP`, no C FFI, no
  external Lake deps.  Sized for the Jupyter Server REST surface
  used by `kernel_execute` (`GET /api/kernels`, `POST /api/kernels`,
  `POST /api/kernels/<id>/interrupt`, …); not a general-purpose
  client.

  Limitations (deliberate, for MVP):
    - HTTP/1.1 plaintext only, no TLS.
    - `Content-Length`-bodied responses only — no chunked transfer.
    - One request per connection (no keep-alive reuse).
    - Headers are case-insensitively matched on read but exact-cased
      on write.
-/
import Std.Internal.UV.TCP
import Std.Net.Addr
import Lean.Data.Json

namespace XLean.MCP.Net.HTTP

open Std.Internal.UV.TCP
open Std.Net

/-- One HTTP response. `body` is the raw response payload (after
    headers); we don't attempt JSON parsing here so callers can
    handle their own MIME types. -/
structure Response where
  status  : Nat
  headers : Array (String × String)
  body    : String
  deriving Inhabited

/-- Block on a `Promise (Except IO.Error α)` returned by libuv,
    re-throwing the libuv error as a Lean `IO.userError` if any. -/
private def awaitPromise [Inhabited α] (p : IO.Promise (Except IO.Error α))
    : IO α := do
  match p.result!.get with
  | .ok a    => pure a
  | .error e => throw e

/-- Build a `SocketAddress` for `127.0.0.1:<port>`. -/
def localhost (port : UInt16) : SocketAddress :=
  .v4 { addr := { octets := #v[127, 0, 0, 1] }, port }

/-- Receive bytes from `s` until the libuv stream returns `none`
    (server closed) or the result exceeds `maxBytes`.  Each chunk is
    capped at 64 KB on the wire.

    Jupyter Server's API responses are small (single-digit KB even
    for `GET /api/sessions`), so this naive "read until close" model
    is fine for the MVP. -/
private partial def recvAll (s : Socket) (maxBytes : Nat := 1 <<< 20) : IO ByteArray := do
  let rec loop (acc : ByteArray) : IO ByteArray := do
    if acc.size ≥ maxBytes then return acc
    let chunkP ← Socket.recv? s (UInt64.ofNat (64 * 1024))
    match ← awaitPromise chunkP with
    | none       => return acc
    | some chunk =>
      if chunk.size == 0 then return acc
      loop (acc ++ chunk)
  loop ByteArray.empty

/-- Parse the response status line + headers + body.  Splits on the
    first `\r\n\r\n`; everything after is the body.  Status line is
    `HTTP/1.1 <code> <reason>\r\n`. -/
private def parseHead (raw : String)
    : Except String (Nat × Array (String × String) × String) := do
  match raw.splitOn "\r\n\r\n" with
  | [] | [_] =>
    .error "no header / body separator"
  | head :: rest =>
    let body := "\r\n\r\n".intercalate rest   -- restore any literal `\r\n\r\n` in body
    let lines := (head.splitOn "\r\n").toArray
    if lines.size = 0 then
      .error "empty response"
    else
      let statusLine := lines[0]!
      let parts := statusLine.splitOn " "
      if parts.length < 2 then
        .error s!"malformed status line: {statusLine}"
      else
        let some statusN := parts[1]!.toNat?
          | .error s!"non-numeric status: {parts[1]!}"
        let headers : Array (String × String) := lines.foldl (init := #[]) fun acc line =>
          match line.splitOn ":" with
          | k :: rest =>
            let v := (":".intercalate rest).trim
            acc.push (k.toLower.trim, v)
          | _ => acc
        .ok (statusN, headers, body)

/-- Send one HTTP request and read the response. -/
def request (method : String) (host : String) (port : UInt16)
    (path : String) (headers : List (String × String) := [])
    (body : String := "") : IO Response := do
  let s ← Socket.new
  -- Open the connection.
  let connectP ← Socket.connect s (localhost port)
  awaitPromise connectP
  -- Build the request bytes.
  let baseHeaders : List (String × String) :=
    [ ("Host", s!"{host}:{port}")
    , ("Connection", "close")
    , ("Accept", "application/json")
    , ("Content-Length", toString body.length)
    , ("Content-Type", "application/json") ]
  let allHeaders := baseHeaders ++ headers
  let headerLines := String.join (allHeaders.map fun (k, v) => s!"{k}: {v}\r\n")
  let reqStr := s!"{method} {path} HTTP/1.1\r\n{headerLines}\r\n{body}"
  let sendP ← Socket.send s #[reqStr.toUTF8]
  awaitPromise sendP
  -- Read the entire response, then split into head / body.
  let raw ← recvAll s
  let rawStr := String.fromUTF8! raw
  match parseHead rawStr with
  | .error e => throw (IO.userError s!"HTTP parse: {e}")
  | .ok (status, headers, body) =>
    pure { status, headers, body }

/-- Convenience: GET. -/
def get (host : String) (port : UInt16) (path : String) : IO Response :=
  request "GET" host port path

/-- Convenience: POST with a JSON body. -/
def postJson (host : String) (port : UInt16) (path : String) (body : Lean.Json) : IO Response :=
  request "POST" host port path (body := body.compress)

/-- Try to JSON-parse `r.body`.  Throws an `IO.userError` if the
    response status indicates failure or the body isn't JSON. -/
def Response.json (r : Response) : IO Lean.Json := do
  if r.status < 200 || r.status >= 300 then
    throw (IO.userError s!"HTTP {r.status}: {r.body}")
  match Lean.Json.parse r.body with
  | .ok j    => pure j
  | .error e => throw (IO.userError s!"HTTP body not JSON: {e}")

end XLean.MCP.Net.HTTP
