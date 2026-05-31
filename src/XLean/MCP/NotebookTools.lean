/-
  MCP/NotebookTools — read / edit `.ipynb` files cell by cell.

  .ipynb is plain JSON with a `cells` array.  Each cell has
  `cell_type` (code / markdown / raw), `source` (string array — one
  entry per line), and optionally `outputs` (for code cells).

  These tools never touch the kernel; they're purely structural
  edits.  Re-evaluating cells against Lean is a separate call (see
  `notebook_evaluate`, planned for a follow-up).
-/

import XLean.MCP.Protocol

namespace XLean.MCP

open Lean (Json)

/-- Join an .ipynb cell's `source` field (an array of strings, one
    per line) into a single string the way notebooks render it. -/
private def joinSource (src : Json) : String :=
  match src with
  | .arr xs => String.join (xs.toList.map fun j =>
      match j with
      | .str s => s
      | _ => "")
  | .str s => s  -- some notebooks store source as a flat string
  | _ => ""

/-- Split a string back into the line-array form .ipynb uses for
    `source`.  Preserve trailing newlines per Jupyter convention. -/
private def splitSource (s : String) : Json :=
  let lines := s.splitOn "\n"
  -- Add back the \n on every line except the last (matches how
  -- JupyterLab writes notebooks).
  let withNl : List String := match lines.reverse with
    | [] => []
    | last :: rest => rest.reverse.map (· ++ "\n") ++ [last]
  Json.arr (withNl.map Json.str).toArray

/-- `notebook_read`: parse `path` and return a summary of every cell:
    its index, type, and source. -/
def tool_notebook_read : ToolInfo × Handler :=
  let info : ToolInfo :=
    { name := "notebook_read"
      description :=
        "Read a .ipynb file and return a JSON-stringified array of "
        ++ "{index, cell_type, source} entries.  Outputs are omitted "
        ++ "to keep the response small; use file_read to see raw JSON."
      inputSchema := Json.mkObj
        [ ("type", "object")
        , ("properties", Json.mkObj
            [ ("path", Json.mkObj
                [("type", "string"), ("description", "Path to the .ipynb file.")])
            ])
        , ("required", Json.arr #["path"])
        ]
    }
  let h : Handler := fun params => do
    match params.getObjValAs? String "path" with
    | .error _ => return .error (-32602, "Missing required parameter: path")
    | .ok path =>
      try
        let content ← IO.FS.readFile path
        match Json.parse content with
        | .error e => return .error (-32000, s!"notebook_read: invalid JSON in {path}: {e}")
        | .ok nb =>
          let cells := nb.getObjVal? "cells" |>.toOption.getD (Json.arr #[])
          let summary :=
            match cells with
            | .arr arr => Json.arr (arr.mapIdx fun i (cell : Json) =>
                let ty := Json.getObjValAs? cell String "cell_type" |>.toOption.getD ""
                let src := Json.getObjVal? cell "source" |>.toOption.getD Json.null
                Json.mkObj
                  [ ("index",     Json.num (i : Int))
                  , ("cell_type", ty)
                  , ("source",    joinSource src)
                  ])
            | _ => Json.arr #[]
          return .ok (textContent summary.pretty)
      catch e =>
        return .error (-32000, s!"notebook_read failed: {e.toString}")
  (info, h)

/-- `notebook_edit`: modify a single cell or insert/delete one.

    Three modes selected by `mode`:
      - "replace": overwrite cell at `index` with `source` (and
                   optionally change `cell_type`)
      - "insert":  insert a new cell at `index`, shifting later cells
                   down (use `index = length` to append)
      - "delete":  remove the cell at `index`

    Everything outside the targeted cell is preserved byte-for-byte
    where possible (we round-trip through Json, which normalises
    whitespace but not structure). -/
def tool_notebook_edit : ToolInfo × Handler :=
  let info : ToolInfo :=
    { name := "notebook_edit"
      description :=
        "Modify a .ipynb file by replacing, inserting, or deleting a "
        ++ "single cell.  `mode` is \"replace\", \"insert\", or \"delete\". "
        ++ "For replace/insert, `source` is the cell text (the writer "
        ++ "splits it into Jupyter's line-array form).  Optional "
        ++ "`cell_type` defaults to \"code\"."
      inputSchema := Json.mkObj
        [ ("type", "object")
        , ("properties", Json.mkObj
            [ ("path",      Json.mkObj
                [("type", "string"), ("description", "Path to the .ipynb file.")])
            , ("mode",      Json.mkObj
                [("type", "string"), ("description", "replace | insert | delete")])
            , ("index",     Json.mkObj
                [("type", "integer"), ("description", "Target cell index (0-based).")])
            , ("source",    Json.mkObj
                [("type", "string"), ("description", "Cell source (replace/insert).")])
            , ("cell_type", Json.mkObj
                [("type", "string"), ("description", "code | markdown | raw (default: code).")])
            ])
        , ("required", Json.arr #["path", "mode", "index"])
        ]
    }
  let h : Handler := fun params => do
    let path?  := params.getObjValAs? String "path"  |>.toOption
    let mode?  := params.getObjValAs? String "mode"  |>.toOption
    let index? := params.getObjValAs? Nat    "index" |>.toOption
    match path?, mode?, index? with
    | some path, some mode, some idx =>
      try
        let content ← IO.FS.readFile path
        match Json.parse content with
        | .error e => return .error (-32000, s!"invalid JSON in {path}: {e}")
        | .ok nb =>
          let cellsJ := nb.getObjVal? "cells" |>.toOption.getD (Json.arr #[])
          let cells : Array Json :=
            match cellsJ with | .arr a => a | _ => #[]
          let buildCell (src : String) (ty : String) : Json :=
            Json.mkObj
              [ ("cell_type",       ty)
              , ("metadata",        Json.mkObj [])
              , ("source",          splitSource src)
              , ("execution_count", Json.null)
              , ("outputs",         Json.arr #[])
              ]
          let cellType := params.getObjValAs? String "cell_type" |>.toOption.getD "code"
          let source   := params.getObjValAs? String "source"    |>.toOption.getD ""
          let newCells : Except String (Array Json) :=
            match mode with
            | "replace" =>
              if idx ≥ cells.size then .error s!"index {idx} out of range (size {cells.size})"
              else .ok (cells.set! idx (buildCell source cellType))
            | "insert" =>
              if idx > cells.size then .error s!"index {idx} out of range for insert (size {cells.size})"
              else .ok (cells.insertIdx! idx (buildCell source cellType))
            | "delete" =>
              if idx ≥ cells.size then .error s!"index {idx} out of range (size {cells.size})"
              else .ok (cells.eraseIdx! idx)
            | _ =>
              .error s!"unknown mode: {mode}"
          match newCells with
          | .error e => return .error (-32602, e)
          | .ok updated =>
            let nb' := nb.setObjVal! "cells" (Json.arr updated)
            IO.FS.writeFile path nb'.pretty
            return .ok (textContent s!"{mode} ok — notebook now has {updated.size} cells")
      catch e =>
        return .error (-32000, s!"notebook_edit failed: {e.toString}")
    | _, _, _ =>
      return .error (-32602, "Missing required parameters: path, mode, index")
  (info, h)

end XLean.MCP
