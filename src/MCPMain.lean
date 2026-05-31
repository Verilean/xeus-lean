/-
  xlean-mcp — MCP server CLI entry point.

  Run as the MCP host's stdio child:

    $ xlean-mcp

  No arguments yet; v1 will add `--port` for HTTP+SSE and probably
  `--workspace=DIR` to scope project-aware tools.
-/

import XLean.MCP

def main : IO Unit := do
  let sess ← IO.mkRef XLean.MCP.LeanSession.fresh
  let server := XLean.MCP.buildServer sess
  XLean.MCP.runStdio server
