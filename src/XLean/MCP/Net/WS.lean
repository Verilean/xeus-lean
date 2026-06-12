/-
  XLean.MCP.Net.WS — Minimal RFC 6455 WebSocket client.

  Built directly on `Std.Internal.UV.TCP`.  Sized for talking to
  Jupyter Server's kernel channels endpoint:

      ws://localhost:PORT/api/kernels/<id>/channels?session_id=<sid>

  Scope (MVP):
    - Plaintext (`ws://`) only, no TLS.
    - Text frames only (opcode 0x1) — Jupyter messages are JSON.
    - Single-fragment frames (FIN always 1 on send; we assume the
      server doesn't fragment its responses in practice).
    - Skip Sec-WebSocket-Accept verification on the client side
      (Jupyter Server is trusted here).
    - Fixed 4-byte mask on send.  The spec requires only that the
      MASK bit be set; randomness is a defence-in-depth measure
      against caching-proxy attacks that doesn't apply to a direct
      localhost socket.
    - No ping / pong handling; Jupyter Server doesn't require it
      for short-lived execute_request flows.
-/
import Std.Internal.UV.TCP
import Std.Net.Addr
import XLean.MCP.Net.HTTP

namespace XLean.MCP.Net.WS

open Std.Internal.UV.TCP
open Std.Net

/-- A live WebSocket session: just the underlying TCP socket plus
    an internal read buffer for surplus bytes the previous recv
    pulled past the end of one frame. -/
structure Session where
  socket    : Socket
  /-- Bytes we've pulled off the wire but not yet handed back as
      part of a frame body.  The next `recvFrame` consumes from
      here before issuing another `Socket.recv?`. -/
  carryRef  : IO.Ref ByteArray

/-- Block on a libuv promise.  Local copy of HTTP's helper to keep
    this module standalone. -/
private def awaitPromise [Inhabited α] (p : IO.Promise (Except IO.Error α))
    : IO α := do
  match p.result!.get with
  | .ok a    => pure a
  | .error e => throw e

/-- Read at least `n` bytes from the socket.  Borrows from the
    `carry` buffer first, refills from the socket as needed. -/
private partial def readN (sess : Session) (n : Nat) : IO ByteArray := do
  let rec loop (buf : ByteArray) : IO ByteArray := do
    if buf.size ≥ n then return buf
    let chunkP ← Socket.recv? sess.socket (UInt64.ofNat (max 4096 (n - buf.size)))
    match ← awaitPromise chunkP with
    | none =>
      throw (IO.userError s!"WS: EOF after {buf.size} bytes, wanted {n}")
    | some chunk => loop (buf ++ chunk)
  let carry ← sess.carryRef.get
  let merged ← loop carry
  -- Split: first n bytes returned, remainder back into carry.
  let head := merged.extract 0 n
  let tail := merged.extract n merged.size
  sess.carryRef.set tail
  pure head

/-- Convert two bytes (big-endian) to a `Nat`. -/
@[inline] private def beU16 (b : ByteArray) (off : Nat) : Nat :=
  (b[off]!.toNat <<< 8) ||| b[off + 1]!.toNat

/-- Convert eight bytes (big-endian) to a `Nat`. -/
@[inline] private def beU64 (b : ByteArray) (off : Nat) : Nat := Id.run do
  let mut acc := 0
  for i in [0:8] do
    acc := (acc <<< 8) ||| b[off + i]!.toNat
  pure acc

/-- Receive one full text-frame payload from the server.  Returns
    `none` on a Close frame (opcode 0x8). -/
partial def recvText (sess : Session) : IO (Option String) := do
  -- Two-byte minimum header.
  let head ← readN sess 2
  let b0 := head[0]!
  let b1 := head[1]!
  let opcode := b0.toNat &&& 0x0F
  let masked := (b1.toNat &&& 0x80) ≠ 0
  let len7   := b1.toNat &&& 0x7F
  let payloadLen ← match len7 with
    | 126 => do
      let ext ← readN sess 2
      pure (beU16 ext 0)
    | 127 => do
      let ext ← readN sess 8
      pure (beU64 ext 0)
    | n   => pure n
  let mask ← if masked then readN sess 4 else pure ByteArray.empty
  let payload ← readN sess payloadLen
  match opcode with
  | 0x8 => return none           -- Close
  | 0x9 | 0xA =>
    -- Ping / pong — ignore, keep reading.  (Server-initiated ping
    -- is rare on a short-lived execute_request socket.)
    recvText sess
  | 0x1 =>
    -- Text.  Unmask if needed (servers shouldn't mask, per RFC).
    let bytes : ByteArray :=
      if masked && mask.size == 4 then Id.run do
        let mut out : ByteArray := ByteArray.empty
        for i in [0:payload.size] do
          out := out.push (payload[i]! ^^^ mask[i % 4]!)
        pure out
      else
        payload
    pure (some (String.fromUTF8! bytes))
  | _ =>
    -- Binary / continuation / unknown.  Treat as fatal for MVP.
    throw (IO.userError s!"WS: unsupported opcode {opcode}")

/-- Constant mask.  Acceptable per RFC for non-hostile transport
    (localhost socket — there's no caching proxy to attack). -/
private def maskBytes : ByteArray :=
  ByteArray.mk #[0x12, 0x34, 0x56, 0x78]

/-- XOR-mask `payload` with `maskBytes`. -/
private def maskPayload (payload : ByteArray) : ByteArray := Id.run do
  let mut out : ByteArray := ByteArray.empty
  for i in [0:payload.size] do
    out := out.push (payload[i]! ^^^ maskBytes[i % 4]!)
  pure out

/-- Send one text frame.  Always FIN, always opcode 0x1, always
    masked. -/
def sendText (sess : Session) (msg : String) : IO Unit := do
  let payload := msg.toUTF8
  let len := payload.size
  let mut header : ByteArray := ByteArray.empty
  -- byte 0: FIN=1 + opcode=text (0x1)
  header := header.push 0x81
  -- byte 1: MASK=1 + length encoding
  if len < 126 then
    header := header.push (UInt8.ofNat (0x80 ||| len))
  else if len < (1 <<< 16) then
    header := header.push (UInt8.ofNat (0x80 ||| 126))
    header := header.push (UInt8.ofNat ((len >>> 8) &&& 0xFF))
    header := header.push (UInt8.ofNat (len &&& 0xFF))
  else
    header := header.push (UInt8.ofNat (0x80 ||| 127))
    -- Big-endian 64-bit length.
    for i in [0:8] do
      let shift := 8 * (7 - i)
      header := header.push (UInt8.ofNat ((len >>> shift) &&& 0xFF))
  -- 4-byte mask key.
  header := header ++ maskBytes
  let masked := maskPayload payload
  let frame := header ++ masked
  let p ← Socket.send sess.socket #[frame]
  awaitPromise p

/-- Return `true` iff `s` contains `\r\n\r\n` (HTTP head end). -/
private def hasHeadEnd (s : String) : Bool :=
  let p := s.find "\r\n\r\n"
  p ≠ s.endPos

/-- Receive bytes from `s` until we've seen `\r\n\r\n` (HTTP head
    terminator).  Returns the bytes consumed (head + any extra)
    so the caller can stash the extras back into the carry buffer. -/
private partial def readUntilHeadEnd (s : Socket) : IO ByteArray := do
  let rec loop (acc : ByteArray) : IO ByteArray := do
    if hasHeadEnd (String.fromUTF8! acc) then
      return acc
    let chunkP ← Socket.recv? s 4096
    match ← awaitPromise chunkP with
    | none       => throw (IO.userError "WS handshake: EOF before headers")
    | some chunk =>
      if chunk.size == 0 then
        throw (IO.userError "WS handshake: empty chunk")
      loop (acc ++ chunk)
  loop ByteArray.empty

/-- Open a WebSocket connection to `localhost:port` with the given
    path (must include any query string).  Throws on non-101
    response.  Returns a live `Session` ready for `sendText` /
    `recvText`. -/
def connect (port : UInt16) (path : String) (host : String := "localhost") : IO Session := do
  let s ← Socket.new
  let connectP ← Socket.connect s (HTTP.localhost port)
  awaitPromise connectP
  -- HTTP upgrade handshake.  Sec-WebSocket-Key is the
  -- RFC 6455 example nonce; the server's matching
  -- Sec-WebSocket-Accept is computed but we don't verify it
  -- (handshake bytes don't carry security in a trusted-localhost
  -- setting).
  let req := String.join [
    s!"GET {path} HTTP/1.1\r\n",
    s!"Host: {host}:{port}\r\n",
    "Upgrade: websocket\r\n",
    "Connection: Upgrade\r\n",
    "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n",
    "Sec-WebSocket-Version: 13\r\n",
    "\r\n"
  ]
  let sendP ← Socket.send s #[req.toUTF8]
  awaitPromise sendP
  let raw ← readUntilHeadEnd s
  let rawStr := String.fromUTF8! raw
  -- Status line.
  let firstLine := rawStr.splitOn "\r\n" |>.head!
  unless firstLine.startsWith "HTTP/1.1 101" do
    throw (IO.userError s!"WS upgrade failed: {firstLine}")
  -- Stash any bytes past the head separator into the carry buffer
  -- so the first `recvText` doesn't re-issue a TCP read for them.
  let parts := rawStr.splitOn "\r\n\r\n"
  let body := match parts with
    | _ :: rest => "\r\n\r\n".intercalate rest
    | []        => ""
  let carryRef ← IO.mkRef body.toUTF8
  pure { socket := s, carryRef }

/-- Close the underlying TCP socket.  We don't send a Close frame
    — Jupyter Server doesn't care for a short-lived request. -/
def close (sess : Session) : IO Unit := do
  let p ← Socket.shutdown sess.socket
  let _ ← awaitPromise p
  pure ()

end XLean.MCP.Net.WS
