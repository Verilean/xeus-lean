# Chapter 12 — Sockets and networking

Lean 4.28 ships a `Std.Net` API on top of `libuv` for TCP and
UDP, plus a small HTTP-fetch helper (`Std.Internal.Http` is not
yet stable; we use `curl` for HTTP examples to keep the chapter
toolchain-agnostic).

> JupyterLite caveat: again, the browser kernel doesn't have raw
> sockets — there's no `libuv` underneath. Run these examples in
> the native kernel.

This chapter covers two layers:

- **Sockets** — `Std.Net.TCP` for TCP clients and servers
- **HTTP** — sketch with `IO.Process.run "curl"` for the
  ubiquitous case

## 12.1 The model

`Std.Net.TCP.Socket` is a non-blocking TCP socket. Operations
return `IO`-actions; the underlying event loop is owned by
`Lean.IO` and shared with file I/O / timers / processes.

There are two relevant types:

- `TCP.Socket` — a connected socket (client or accepted by
  server), supports `.send` and `.receive`
- `TCP.Server` — a listening socket, supports `.accept`

The everyday combinators we use below:

| Call                                    | Effect |
|-----------------------------------------|--------|
| `TCP.Socket.connect addr port : IO Socket` | client connect |
| `TCP.Server.bind addr port : IO Server`    | bind+listen |
| `server.accept : IO Socket`              | accept one client |
| `sock.send bytes : IO Unit`              | write `ByteArray` |
| `sock.receive max : IO ByteArray`        | read up to N bytes |
| `sock.close : IO Unit`                   | close |

(API names settled in 4.28; older versions had `Std.Internal.UV`-
prefixed equivalents.)

## 12.2 A trivial echo client

```lean
import Std.Net

-- Talk to a local "discard"-style server we'll write in the
-- next cell.  For now, here's just the structure:
#eval show IO Unit from do
  -- Pretend a server is running on 127.0.0.1:7777.
  -- let sock ← Std.Net.TCP.Socket.connect "127.0.0.1" 7777
  -- sock.send (String.toUTF8 "hello, server\n")
  -- let reply ← sock.receive 1024
  -- IO.println s!"reply: {String.fromUTF8! reply}"
  IO.println "(skipped — would need a running peer)"
```
```output
(skipped — would need a running peer)
```

Real client examples are deferred until we have a server in
the next section to talk to.

## 12.3 A simple TCP server

The pattern: bind, then loop accepting connections, handing each
off to a task (we get to `IO.asTask` in Chapter 13).

```lean
import Std.Net

partial def serveOne (sock : Std.Net.TCP.Socket) : IO Unit := do
  let buf ← sock.receive 1024
  let req := String.fromUTF8! buf
  let reply := s!"got {buf.size} bytes: {req.trim}\n"
  sock.send (String.toUTF8 reply)
  sock.close

#eval show IO Unit from do
  -- start the server (will block until a client connects)
  -- let server ← Std.Net.TCP.Server.bind "127.0.0.1" 0   -- 0 = random port
  -- IO.println s!"listening on port {server.localPort}"
  -- let client ← server.accept
  -- serveOne client
  -- server.close
  IO.println "(server skeleton — uncomment to run a live server)"
```
```output
(server skeleton — uncomment to run a live server)
```

The full echo-server / echo-client loop is a few dozen lines and
runs reliably under the native kernel; we leave the live
end-to-end demo as an exercise so the chapter renders without
needing a daemon.

## 12.4 HTTP via `curl` (the pragmatic path)

`Std.Net` is fine for TCP/UDP, but for HTTP-with-everything
(redirects, TLS, gzip, chunked, etc.) it's currently saner to
shell out to `curl`. It's available on every Linux/macOS box
and behaves identically across them.

### GET

```lean
def httpGet (url : String) : IO String := do
  IO.Process.run {
    cmd := "curl"
    args := #["-sSL", "--max-time", "10", url]
  }

#eval show IO Unit from do
  let body ← httpGet "https://example.com"
  IO.println (body.take 200 ++ "...")
```
```output
<!doctype html>
<html>
<head>
    <title>Example Domain</title>
...
```

### POST with JSON

```lean
import Lean.Data.Json
open Lean

def httpPostJson (url : String) (j : Json) : IO String := do
  IO.Process.run {
    cmd := "curl"
    args := #["-sSL", "--max-time", "10",
              "-H", "Content-Type: application/json",
              "-d", j.compress, url]
  }

-- Talk to httpbin.org (echoes the request back at you):
#eval show IO Unit from do
  let payload : Json := Json.mkObj [("name", "lean"), ("year", 2026)]
  let reply ← httpPostJson "https://httpbin.org/post" payload
  IO.println (reply.take 400)
```
```output
{
  "args": {},
  "data": "{\"name\":\"lean\",\"year\":2026}",
  "files": {},
  "form": {},
  "headers": {
    "Accept": "*/*",
    "Content-Length": "27",
    "Content-Type": "application/json",
    "Host": "httpbin.org",
    "User-Agent": "curl/8.5.0",
...
```

(If you run the cell, you'll see httpbin echoes the JSON back
under `"data"` — proof the round-trip worked.)

### Parsing the reply

```lean
def httpGetJson (url : String) : IO Json := do
  let txt ← httpGet url
  match Json.parse txt with
  | .ok j    => pure j
  | .error e => throw (IO.userError s!"JSON parse failed: {e}")

#eval show IO Unit from do
  let j ← httpGetJson "https://httpbin.org/get"
  IO.println (j.getObjValAs? String "url" |>.toOption.getD "?")
```
```output
https://httpbin.org/get
```

## 12.5 UDP

```lean
import Std.Net

#eval show IO Unit from do
  -- let sock ← Std.Net.UDP.Socket.bind "127.0.0.1" 0
  -- sock.sendTo "127.0.0.1" 4242 (String.toUTF8 "ping")
  -- let (peer, bytes) ← sock.receiveFrom 1024
  -- IO.println s!"{peer.addr}:{peer.port} → {bytes.size} bytes"
  -- sock.close
  IO.println "(UDP skeleton — same shape as TCP, with sendTo/receiveFrom)"
```
```output
(UDP skeleton — same shape as TCP, with sendTo/receiveFrom)
```

UDP is just TCP without `connect` / `accept` — `sendTo` and
`receiveFrom` carry the peer address with each datagram.

## 12.6 Timeouts and cancellation

`Std.Net` doesn't expose per-call timeouts directly; the idiom
is to race the socket op against a timer using `IO.asTask`
(Chapter 13). For HTTP via `curl`, pass `--max-time`.

## 12.7 When to drop to raw sockets

| Need                                  | Pick |
|---------------------------------------|------|
| HTTP fetch / POST                     | `curl` shell-out |
| Custom binary protocol over TCP       | `Std.Net.TCP.Socket` |
| Real-time / low-latency UDP           | `Std.Net.UDP.Socket` |
| Embedded HTTP server in Lean          | rolls your own on `TCP.Server` (no batteries) |
| WebSockets, HTTP/2, TLS handshake     | `curl` / shell out (today); Lean lacks them |

The "use `curl` for HTTP" advice is conservative. As `Std.Net`
matures, expect a native HTTP client in the standard library —
this chapter will get updated.

## 12.8 Recap

You can now:

- open / close TCP sockets via `Std.Net.TCP.Socket.connect` +
  `.send` / `.receive` / `.close`
- bind / accept on `Std.Net.TCP.Server`
- send / receive UDP datagrams with `.sendTo` / `.receiveFrom`
- do HTTP GET / POST / JSON-decode by shelling out to `curl` +
  `Lean.Data.Json`

Next: [Chapter 13 (Tasks, refs, mutexes)](Ch13_Concurrency.md) —
how to do all of the above *concurrently*.
