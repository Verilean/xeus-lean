# MCP server: `xlean-mcp`

`xlean-mcp` is an [MCP](https://spec.modelcontextprotocol.io/) server
that lets a local agent (Claude Code, Cursor, any MCP-compatible
host) drive xeus-lean programmatically: evaluate Lean snippets, read
and edit notebooks, search the project, manipulate files.

It's a thin Lean 4 binary that speaks JSON-RPC 2.0 over stdio.  No
external runtime; once the Lean executable is built, you have it.

## Build

```bash
git clone https://github.com/Verilean/xeus-lean
cd xeus-lean
lake build xlean-mcp
# binary at .lake/build/bin/xlean-mcp
```

That's it.  `xlean-mcp` doesn't talk to a running kernel today (v1
roadmap, see *Limitations* below); it's a stand-alone executable.

## Connect from Claude Code

Edit your MCP config (`~/.claude/mcp.json` or the project-local
equivalent, depending on your Claude Code version) and add:

```json
{
  "mcpServers": {
    "xlean": {
      "command": "/absolute/path/to/xeus-lean/.lake/build/bin/xlean-mcp"
    }
  }
}
```

Restart Claude Code.  In a new chat, the `xlean` tools should appear
in the agent's available capabilities — typically you'll see them
listed alongside the built-in `read`, `edit`, `bash` tools.

## Connect from any MCP host

Anything that can spawn a child process and speak stdio MCP works.
Pass nothing on the command line; the server hard-codes the
default workspace as its current working directory.

For protocol-level testing without a host, the [MCP inspector](https://github.com/modelcontextprotocol/inspector)
gives you a GUI.

## Tool catalogue (v0.2)

### `lean_eval`

Send a snippet to a fresh `lean` process and return its output.

```json
{
  "name": "lean_eval",
  "arguments": { "code": "#eval 1 + 2" }
}
→ "3\n"
```

Caveat: each call sees an empty environment.  Definitions from one
`lean_eval` aren't visible in the next.  v1 will fix this by sharing
the running REPL's env.

### `file_read`

```json
{
  "name": "file_read",
  "arguments": {
    "path": "README.md",
    "offset": 1,
    "limit": 5
  }
}
```

`offset` is a 1-indexed line number.  `limit` is the max lines to
return; `0` (default) means "to end of file".

### `file_write`

```json
{
  "name": "file_write",
  "arguments": {
    "path": "/path/to/file.lean",
    "content": "def foo : Nat := 42\n"
  }
}
```

Overwrites the file with `content`.  Does not create parent
directories.

### `project_search`

```json
{
  "name": "project_search",
  "arguments": {
    "pattern": "showDiagram",
    "glob": "*.lean"
  }
}
```

Wraps `ripgrep`.  `path` (subdirectory) and `glob` (file pattern)
are optional filters.  Returns `file:line: matched_line` rows on
stdout.

### `notebook_read`

```json
{
  "name": "notebook_read",
  "arguments": { "path": "notebooks/mathlib-demo.ipynb" }
}
→ [
    { "index": 0, "cell_type": "markdown",
      "source": "# Mathlib in the browser\n..." },
    { "index": 1, "cell_type": "code",
      "source": "%load mathlib" },
    ...
  ]
```

Outputs are omitted to keep the response small; if you need the raw
JSON, use `file_read`.

### `notebook_edit`

```json
{
  "name": "notebook_edit",
  "arguments": {
    "path": "notebooks/scratch.ipynb",
    "mode": "replace",
    "index": 1,
    "source": "import Mathlib.Tactic.Ring\n",
    "cell_type": "code"
  }
}
```

Three modes: `"replace"`, `"insert"`, `"delete"`.

- `replace` overwrites the cell at `index`.
- `insert` adds a new cell at `index`, shifting later cells down.
  Use `index == cells.length` to append.
- `delete` removes the cell at `index`.

For `replace`/`insert`, `source` is the cell text and `cell_type`
defaults to `"code"` (other valid values: `"markdown"`, `"raw"`).

The writer splits `source` into Jupyter's per-line array form
automatically.

## Example session

A typical agent workflow:

> User: "Add a cell that proves `example : 1 + 1 = 2 := rfl` to
>        `scratch.ipynb`."

Agent does:

1. `notebook_read scratch.ipynb` — sees N existing cells.
2. `notebook_edit scratch.ipynb mode=insert index=N
   source="example : 1 + 1 = 2 := rfl"` — appends.
3. `notebook_read scratch.ipynb` again — verifies cell N is in place.

Or:

> User: "Where in the codebase does `xeus_ffi.cpp` call `dup2`?"

Agent does:

1. `project_search pattern="dup2" path="src/xeus_ffi.cpp"` — gets
   line numbers.
2. `file_read src/xeus_ffi.cpp offset=355 limit=20` — pulls the
   relevant block.
3. Summarises.

## Limitations

- **No env persistence in `lean_eval`.**  Each call spawns a fresh
  `lean` process.  v1 (#63 in the project todo list) will host the
  MCP server inside a running xeus-lean kernel so the REPL env is
  shared across calls — at that point `lean_eval` will behave like
  notebook cells.
- **No browser-side access.**  The MCP server can't see what's in a
  user's open JupyterLite tab.  That needs a service-worker shim in
  the WASM build (#64 in the todo list).
- **`project_search` cwd.**  ripgrep runs in whatever directory the
  MCP host launched the server from.  Workspace-relative search
  needs an explicit `path` argument.
- **No `lake_build` / `lake_test` tool yet.**  Slated for v0.3.

## What the protocol looks like on the wire

If you want to script `xlean-mcp` without an MCP host, here's the
minimum: each message is `Content-Length: N\r\n\r\n<N bytes of JSON>`,
JSON-RPC 2.0 envelopes, dispatched by `method`:

```text
# client → server
Content-Length: 88

{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}

# server → client
Content-Length: 175

{"id":1,"jsonrpc":"2.0","result":{"capabilities":{"tools":{}},
"protocolVersion":"2024-11-05","serverInfo":{"name":"xlean-mcp",
"version":"0.1.0"}}}
```

Then `tools/list`, then `tools/call`.  See the [MCP spec][mcp] for
the full method list.

[mcp]: https://spec.modelcontextprotocol.io/
