/-
  XLean.MCP — entry point that pulls together the protocol layer
  and the tool registry.

  See sub-modules for details:
    XLean.MCP.Protocol    — JSON-RPC transport + dispatch
    XLean.MCP.LeanSession — wrapper around the Lean REPL
    XLean.MCP.Tools       — lifecycle methods + tool catalogue
-/

import XLean.MCP.Protocol
import XLean.MCP.LeanSession
import XLean.MCP.FileTools
import XLean.MCP.NotebookTools
import XLean.MCP.Tools
