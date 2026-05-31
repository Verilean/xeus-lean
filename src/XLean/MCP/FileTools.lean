/-
  MCP/FileTools — `file_read`, `file_write`, `project_search`.

  These are the workhorse "do something with the local filesystem"
  tools that every MCP server ends up with.  Kept narrow on purpose:
  each does exactly one thing and the client composes them.
-/

import XLean.MCP.Protocol

namespace XLean.MCP

open Lean (Json)

/-- `file_read`: return the contents of a file, optionally a slice
    of it.  `offset` and `limit` are 1-indexed line numbers, matching
    how editors talk about files. -/
def tool_file_read : ToolInfo × Handler :=
  let info : ToolInfo := {
    name := "file_read",
    description :=
      "Read the contents of a file as text.  Optional `offset` "
      ++ "and `limit` (1-indexed line numbers) take a slice.",
    inputSchema := Json.mkObj
      [ ("type", "object")
      , ("properties", Json.mkObj
          [ ("path",   Json.mkObj
              [("type", "string"), ("description", "Absolute or workspace-relative path.")])
          , ("offset", Json.mkObj
              [("type", "integer"), ("description", "First line to return (1-indexed).")])
          , ("limit",  Json.mkObj
              [("type", "integer"), ("description", "Max lines to return.")])
          ])
      , ("required", Json.arr #["path"])
      ]
  }
  let h : Handler := fun params => do
    match params.getObjValAs? String "path" with
    | .error _ => return .error (-32602, "Missing required parameter: path")
    | .ok path =>
      let offset := params.getObjValAs? Nat "offset" |>.toOption.getD 1
      let limit  := params.getObjValAs? Nat "limit"  |>.toOption.getD 0
      try
        let content ← IO.FS.readFile path
        if offset == 1 && limit == 0 then
          return .ok (textContent content)
        let lines := content.splitOn "\n"
        let start := offset - 1
        let len := if limit == 0 then lines.length else limit
        let slice := (lines.drop start).take len
        return .ok (textContent (String.intercalate "\n" slice))
      catch e =>
        return .error (-32000, s!"file_read failed: {e.toString}")
  (info, h)

/-- `file_write`: overwrite a file with the given contents.  No
    partial-edit support here — that's the host's job. -/
def tool_file_write : ToolInfo × Handler :=
  let info : ToolInfo :=
    { name := "file_write"
      description :=
        "Overwrite a file with the given content.  Creates the file "
        ++ "if it doesn't exist.  Does not create parent directories."
      inputSchema := Json.mkObj
        [ ("type", "object")
        , ("properties", Json.mkObj
            [ ("path",    Json.mkObj
                [("type", "string"), ("description", "Path to write.")])
            , ("content", Json.mkObj
                [("type", "string"), ("description", "New contents.")])
            ])
        , ("required", Json.arr #["path", "content"])
        ]
    }
  let h : Handler := fun params => do
    let path?    := params.getObjValAs? String "path"    |>.toOption
    let content? := params.getObjValAs? String "content" |>.toOption
    match path?, content? with
    | some path, some content =>
      try
        IO.FS.writeFile path content
        return .ok (textContent s!"wrote {content.length} bytes to {path}")
      catch e =>
        return .error (-32000, s!"file_write failed: {e.toString}")
    | _, _ =>
      return .error (-32602, "Missing required parameters: path and content")
  (info, h)

/-- `project_search`: run ripgrep over the workspace and return the
    raw output.  `pattern` is required; `path` (subdirectory) and
    `glob` (e.g. `*.lean`) are optional filters. -/
def tool_project_search : ToolInfo × Handler :=
  let info : ToolInfo :=
    { name := "project_search"
      description :=
        "Search the workspace for a regex pattern via ripgrep.  "
        ++ "Returns matching lines with file:line: prefixes.  "
        ++ "Optional `path` restricts to a subdirectory; optional "
        ++ "`glob` (e.g. \"*.lean\") restricts to a file pattern."
      inputSchema := Json.mkObj
        [ ("type", "object")
        , ("properties", Json.mkObj
            [ ("pattern", Json.mkObj
                [("type", "string"), ("description", "Regex pattern.")])
            , ("path",    Json.mkObj
                [("type", "string"), ("description", "Subdirectory to search.")])
            , ("glob",    Json.mkObj
                [("type", "string"), ("description", "File glob filter.")])
            ])
        , ("required", Json.arr #["pattern"])
        ]
    }
  let h : Handler := fun params => do
    match params.getObjValAs? String "pattern" with
    | .error _ => return .error (-32602, "Missing required parameter: pattern")
    | .ok pattern =>
      let mut args : Array String := #["--line-number", "--with-filename", "--color=never"]
      if let some g := params.getObjValAs? String "glob" |>.toOption then
        args := args.push s!"--glob={g}"
      args := args.push pattern
      if let some p := params.getObjValAs? String "path" |>.toOption then
        args := args.push p
      let out ← IO.Process.output { cmd := "rg", args := args }
      -- rg exits 1 when there are no matches; that's not an error
      -- for us.  Return whatever was on stdout (possibly empty).
      return .ok (textContent
        (if out.stdout.isEmpty
          then s!"(no matches for {pattern})"
          else out.stdout))
  (info, h)

end XLean.MCP
