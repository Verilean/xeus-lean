/-
  XLean.MCP.ConvertTools — MCP wrappers around the `Convert` library.

  The `xlean-convert` CLI re-renders a tutorial Markdown chapter
  into a `.ipynb` notebook (Jupyter JSON) and a sibling `.lean`
  (jupytext-style percent format).  Sparkle's
  `docs/tutorial/build-from-md.sh` calls it in batch — fine for CI
  but awful in the middle of a live editing session: the MCP host
  has just amended the `.md`, and now needs to shell out, re-fork
  a Lean process, parse, write, *then* the user reloads their
  browser tab to see the notebook update.

  Exposing the same conversion logic as an MCP tool collapses that
  to one round-trip — edit `.md`, call `markdown_to_notebook`,
  user refreshes.  The pipeline is the same one
  `build-from-md.sh` runs (`Convert.parseMarkdown` →
  `cellsToIpynb` / `cellsToPercent`); we just plumb it through the
  tool registry instead of a CLI invocation.
-/
import XLean.MCP.Protocol
import Convert
import Lean.Data.Json

namespace XLean.MCP

open Lean (Json)

/-- Read the .md at `mdPath`, parse it, and write the
    Jupyter-notebook form at `ipynbPath`.  Pretty-prints the JSON
    so the diff against a previous version is reviewable. -/
private def runMarkdownToNotebook (mdPath ipynbPath : String) : IO Unit := do
  let src ← IO.FS.readFile mdPath
  let cells := Convert.parseMarkdown src
  let json := Convert.cellsToIpynb cells
  -- `pretty` indents at width 2; `compress` would be one line.
  -- The tutorial repo tracks these files in git, so reviewability
  -- wins out over byte count.
  IO.FS.writeFile ipynbPath (json.pretty)

/-- Same, but produces the jupytext `lean:percent` view (the one
    `lake build TutorialNotebooks` ingests). -/
private def runMarkdownToLean (mdPath leanPath : String) : IO Unit := do
  let src ← IO.FS.readFile mdPath
  let cells := Convert.parseMarkdown src
  IO.FS.writeFile leanPath (Convert.cellsToPercent cells)

/-- Render one `Convert.Cell` back to its Markdown form: markdown
    cells emit the body verbatim; code cells become a `` ```lean ``
    fence (matching what `parseMarkdown` recognises).  We ignore
    `outputs` on code cells — they're regenerated on the next
    kernel run anyway. -/
private def cellToMarkdown : Convert.Cell → String
  | .markdown ls =>
    -- `parseMarkdown` strips trailing blank lines on flush, so we
    -- restore one to keep a blank line between cells.
    let body := ls.foldl (fun acc l => acc ++ l ++ "\n") ""
    body ++ "\n"
  | .code ls _ =>
    let body := ls.foldl (fun acc l => acc ++ l ++ "\n") ""
    "```lean\n" ++ body ++ "```\n\n"

/-- Render an entire cell list back to Markdown.  Round-trip with
    `parseMarkdown` is best-effort (whitespace at chapter boundaries
    may differ); cell content survives intact. -/
private def cellsToMarkdown (cells : Array Convert.Cell) : String :=
  cells.foldl (fun acc c => acc ++ cellToMarkdown c) ""

/-- Read a Jupyter `.ipynb` JSON value and extract its cells in the
    shape `Convert.Cell` uses.  Ignores cell `outputs` and
    `execution_count` — only the source matters for `.md`. -/
private def cellsFromIpynb (j : Lean.Json) : Except String (Array Convert.Cell) := do
  let cellsJ ← j.getObjVal? "cells"
  let arr    ← cellsJ.getArr?
  arr.mapM fun c => do
    let kind ← c.getObjValAs? String "cell_type"
    let srcJ ← c.getObjVal? "source"
    -- `source` is either an array of line strings or a single string.
    let lines : Array String ← match srcJ with
      | .arr xs => xs.mapM (·.getStr?)
      | .str s  => pure #[s]
      | _ => .error "cell source must be array or string"
    -- Jupyter cells generally store lines WITH trailing `\n`.
    -- Strip the trailing newline on each so the body becomes the
    -- canonical "one line per element" shape `Convert.Cell` expects.
    let stripped := lines.map fun l =>
      if l.endsWith "\n" then l.dropRight 1 else l
    match kind with
    | "code"     => pure (.code stripped)
    | "markdown" => pure (.markdown stripped)
    | "raw"      => pure (.markdown stripped)  -- treat raw as markdown text
    | other      => .error s!"unknown cell_type: {other}"

/-- `markdown_to_notebook`: regenerate one chapter's `.ipynb` (and
    optionally its `.lean`) from its Markdown source.  The MCP host
    typically calls this immediately after editing a `.md` file so
    the change reaches JupyterLab on the user's next page reload. -/
def tool_markdown_to_notebook : ToolInfo × Handler :=
  let info : ToolInfo :=
    { name := "markdown_to_notebook"
      description :=
        "Re-render a tutorial Markdown chapter to its sibling .ipynb"
        ++ " (and optionally to the .lean percent format `lake build`"
        ++ " ingests).  Same pipeline as the xlean-convert CLI."
        ++ "  Use right after editing a .md so JupyterLab catches up"
        ++ " on the next reload — no host-side rebuild needed."
      inputSchema := Json.mkObj
        [ ("type",       "object")
        , ("properties", Json.mkObj
            [ ("md_path",     Json.mkObj
                [ ("type",        "string")
                , ("description", "Path to the input Markdown chapter (e.g. docs/tutorial/md/Ch03_Sequential.md).")
                ])
            , ("ipynb_path",  Json.mkObj
                [ ("type",        "string")
                , ("description", "Path to write the notebook JSON to (e.g. docs/tutorial/Notebooks/Gen/notebooks/ch03-sequential.ipynb).")
                ])
            , ("lean_path",   Json.mkObj
                [ ("type",        "string")
                , ("description", "Optional: also write a lean:percent file at this path (e.g. docs/tutorial/Notebooks/Gen/Ch03_Sequential.lean).")
                ])
            ])
        , ("required",   Json.arr #["md_path", "ipynb_path"])
        ]
    }
  let handler : Handler := fun params => do
    match params.getObjValAs? String "md_path", params.getObjValAs? String "ipynb_path" with
    | .error _, _ => return .error (-32602, "Missing required parameter: md_path")
    | _, .error _ => return .error (-32602, "Missing required parameter: ipynb_path")
    | .ok mdPath, .ok ipynbPath =>
      try
        runMarkdownToNotebook mdPath ipynbPath
        let leanWritten ← match params.getObjValAs? String "lean_path" with
          | .ok lp => do runMarkdownToLean mdPath lp; pure (some lp)
          | .error _ => pure none
        let body := match leanWritten with
          | some lp => s!"wrote {ipynbPath}\nwrote {lp}"
          | none    => s!"wrote {ipynbPath}"
        return .ok (textContent body)
      catch e =>
        return .error (-32000, s!"markdown_to_notebook: {e.toString}")
  (info, handler)

/-- `notebook_to_markdown`: the inverse direction — read an `.ipynb`,
    walk its cells, and write a Markdown chapter where every
    `markdown` cell is dumped verbatim and every `code` cell is
    wrapped in a ` ```lean ` fence.  The round-trip with
    `markdown_to_notebook` preserves cell content (whitespace at
    cell boundaries can differ).

    Use this when the MCP host has edited a notebook cell directly
    via `notebook_edit` and wants the change to land in the `.md`
    source under git too. -/
def tool_notebook_to_markdown : ToolInfo × Handler :=
  let info : ToolInfo :=
    { name := "notebook_to_markdown"
      description :=
        "Render an .ipynb back to its Markdown chapter form. "
        ++ "Inverse of `markdown_to_notebook` — use after editing "
        ++ "a notebook cell via `notebook_edit` to mirror the change "
        ++ "into the .md source the docker image is built from."
      inputSchema := Json.mkObj
        [ ("type",       "object")
        , ("properties", Json.mkObj
            [ ("ipynb_path", Json.mkObj
                [ ("type",        "string")
                , ("description", "Path to the input .ipynb.")
                ])
            , ("md_path",    Json.mkObj
                [ ("type",        "string")
                , ("description", "Path to write the Markdown chapter to (e.g. docs/tutorial/md/Ch03_Sequential.md).")
                ])
            ])
        , ("required",   Json.arr #["ipynb_path", "md_path"])
        ]
    }
  let handler : Handler := fun params => do
    match params.getObjValAs? String "ipynb_path",
          params.getObjValAs? String "md_path" with
    | .error _, _ => return .error (-32602, "Missing required parameter: ipynb_path")
    | _, .error _ => return .error (-32602, "Missing required parameter: md_path")
    | .ok ipynbPath, .ok mdPath =>
      try
        let raw ← IO.FS.readFile ipynbPath
        match Lean.Json.parse raw with
        | .error e =>
          return .error (-32000, s!"notebook_to_markdown: {ipynbPath} not JSON: {e}")
        | .ok j =>
          match cellsFromIpynb j with
          | .error e =>
            return .error (-32000, s!"notebook_to_markdown: {e}")
          | .ok cells =>
            IO.FS.writeFile mdPath (cellsToMarkdown cells)
            return .ok (textContent s!"wrote {mdPath}")
      catch e =>
        return .error (-32000, s!"notebook_to_markdown: {e.toString}")
  (info, handler)

end XLean.MCP
