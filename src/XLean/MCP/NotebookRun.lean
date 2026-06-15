/-
  XLean.MCP.NotebookRun — `notebook_run_cell` tool.

  Combines the four-step recipe that gives "live UX" when an MCP
  host edits a notebook cell and wants the kernel's output to
  appear in the user's browser WITHOUT a page reload:

    1. Read the .ipynb cell at `cell_index` and pull its source.
    2. Send the source to the running xeus-lean kernel via
       `KernelBridge.execute` and collect the outputs.
    3. Write the outputs back into the .ipynb via Jupyter Server's
       `PUT /api/contents/<path>` (so jupyter-collaboration's
       Y.js doc store hears the update and pushes it to every
       connected client live).
    4. Sign the notebook with `jupyter trust` so the browser is
       willing to render trust-gated MIME types (image/svg+xml,
       text/html) without the user having to mark the doc trusted.

  Without step (4) the browser receives the new outputs over RTC
  but silently drops SVG / HTML payloads — they only re-render
  after a manual reload.  Without step (3) the file is updated
  but jupyter-collaboration's in-memory state is authoritative
  for the open doc and the change never reaches the browser.
  Both steps are needed.

  Caveats:
    - Multi-key MIME bundles are split into one display_data per
      MIME type, because JupyterLab picks the highest-priority
      type within a bundle and hides the others.  An agent that
      wants both build-log text and an SVG waveform visible needs
      them as separate outputs; this tool does that splitting
      automatically.
    - The XSRF flow (GET /lab to grab the `_xsrf` cookie, then
      send it back in both `Cookie` and `X-XSRFToken` headers on
      the PUT) is implemented here because Jupyter Server's
      default config blocks PUT without it.
-/
import XLean.MCP.Protocol
import XLean.MCP.Net.HTTP
import XLean.MCP.KernelBridge
import Lean.Data.Json

namespace XLean.MCP

open Lean (Json)
open XLean.MCP.Net

/-- Substring extract: return the part of `s` after the first
    occurrence of `needle`, or `none` if not present. -/
private def afterSubstr (s : String) (needle : String) : Option String :=
  match s.splitOn needle with
  | _ :: rest :: _ => some rest
  | _              => none

/-- Pull `_xsrf=<value>` out of a `Set-Cookie` header. -/
private def parseXsrf (setCookie : String) : Option String := do
  let rest ← afterSubstr setCookie "_xsrf="
  -- rest is `<value>; expires=...; Path=/`
  match (rest.splitOn ";").head? with
  | none     => none
  | some v   => some v

/-- Hit `GET /lab` so Jupyter Server hands us a fresh `_xsrf`
    cookie, parse it out, and return the value. -/
private def fetchXsrf : IO String := do
  let r ← HTTP.get "localhost" KernelBridge.jupyterPort "/lab"
  let setCookies := r.headers.filterMap fun (k, v) =>
    if k == "set-cookie" then some v else none
  let some xsrf := setCookies.findSome? parseXsrf
    | throw <| IO.userError "no _xsrf cookie in /lab response"
  pure xsrf

/-- Send `PUT /api/contents/<apiPath>` with the notebook JSON.
    Carries the XSRF token in both the cookie and the matching
    header — `jupyter_server` rejects the request if either is
    missing. -/
private def putNotebook (apiPath : String) (nb : Json) (xsrf : String) : IO Unit := do
  let payload := Json.mkObj
    [ ("type", "notebook"), ("format", "json"), ("content", nb) ]
  let r ← HTTP.request "PUT" "localhost" KernelBridge.jupyterPort
    s!"/api/contents/{apiPath}"
    [ ("X-XSRFToken", xsrf), ("Cookie", s!"_xsrf={xsrf}") ]
    payload.compress
  if r.status < 200 || r.status >= 300 then
    throw <| IO.userError s!"PUT /api/contents/{apiPath} → {r.status}: {r.body}"

/-- Default Jupyter Lab notebook root inside the tutorial image.
    `apiPath` for the Contents API is computed by stripping this
    prefix from a filesystem path. -/
private def notebookRoot : String :=
  "/workspace/sparkle/docs/tutorial/Notebooks/Gen/notebooks/"

/-- Convert a workspace-relative or absolute FS path to a path
    suitable for the Contents API.  Falls back to using the input
    verbatim when it doesn't look like it's under `notebookRoot`
    — Jupyter Server will accept either form when it can resolve
    the file. -/
private def toApiPath (fs : String) : String :=
  if fs.startsWith notebookRoot then
    (fs.drop notebookRoot.length).toString
  else if fs.startsWith "docs/tutorial/Notebooks/Gen/notebooks/" then
    (fs.drop "docs/tutorial/Notebooks/Gen/notebooks/".length).toString
  else fs

/-- Resolve to an absolute filesystem path inside the container,
    for `jupyter trust`'s sake.  We can't rely on the working
    directory because `jupyter trust` doesn't accept a notebook
    URI. -/
private def toFsPath (fs : String) : String :=
  if fs.startsWith "/" then fs
  else if fs.startsWith "docs/tutorial/Notebooks/Gen/notebooks/" then
    s!"/workspace/sparkle/{fs}"
  else fs

/-- Sign the notebook so JupyterLab will render trust-gated MIMEs
    (image/svg+xml, text/html, application/javascript) without
    a manual "trust notebook" click. -/
private def trustNotebook (fsPath : String) : IO Unit := do
  let r ← IO.Process.output { cmd := "jupyter", args := #["trust", fsPath] }
  if r.exitCode != 0 then
    IO.eprintln s!"[notebook_run_cell] jupyter trust warning: {r.stderr}"

/-- Read a `.ipynb`, return the parsed JSON. -/
private def readIpynb (path : String) : IO Json := do
  let raw ← IO.FS.readFile path
  match Json.parse raw with
  | .ok j => pure j
  | .error e => throw <| IO.userError s!"parse {path}: {e}"

/-- Coerce a Jupyter `source` field — either a String or an
    Array String of lines — into a single concatenated String. -/
private def sourceToString (src : Json) : String :=
  match src with
  | .str s => s
  | .arr xs =>
    xs.foldl (fun acc x =>
      match x with | .str s => acc ++ s | _ => acc) ""
  | _ => ""

/-- Render a kernel output back into Jupyter's wire format,
    splitting multi-MIME bundles so JupyterLab won't hide the
    low-priority renderer.

    A `display_data` whose `data` carries BOTH `text/plain` and,
    say, `image/svg+xml` gets shown as the SVG only — JupyterLab
    picks the richest MIME and treats the others as fallbacks.
    Splitting them across two `display_data` outputs makes both
    visible. -/
private def outputToCells (o : KernelBridge.Output) : Array Json :=
  match o with
  | .stream name text =>
    #[Json.mkObj
      [ ("output_type", "stream"), ("name", name), ("text", text) ]]
  | .mime data =>
    -- Split each MIME key into its own display_data so JupyterLab
    -- renders all of them.  We enumerate the MIME types xeus-lean's
    -- Display emits (rather than iterating the underlying TreeMap
    -- whose API moves between Lean versions); anything outside this
    -- set falls through as a single combined output.
    let mimes := ["text/plain", "text/html", "image/svg+xml",
                  "image/png", "image/jpeg", "text/markdown",
                  "text/latex", "application/json",
                  "application/vnd.jupyter.widget-view+json"]
    let cells := mimes.foldl (init := #[]) fun acc m =>
      match data.getObjVal? m with
      | .ok v => acc.push (Json.mkObj
          [ ("output_type", "display_data")
          , ("data", Json.mkObj [(m, v)])
          , ("metadata", Json.mkObj [])
          ])
      | .error _ => acc
    if cells.isEmpty then
      -- Unknown MIME bundle — keep it intact rather than dropping.
      #[Json.mkObj
        [ ("output_type", "display_data")
        , ("data", data)
        , ("metadata", Json.mkObj [])
        ]]
    else
      cells
  | .error ename evalue tb =>
    #[Json.mkObj
      [ ("output_type", "error")
      , ("ename", ename)
      , ("evalue", evalue)
      , ("traceback", Json.arr (tb.map Json.str))
      ]]

/-- Replace the cell at `idx` in `cells` with `newCell`. -/
private def setCell (cells : Array Json) (idx : Nat) (newCell : Json) : Array Json :=
  cells.mapIdx fun i c => if i == idx then newCell else c

/-- The combined recipe.  Reads cell source, runs it, embeds the
    outputs back, writes via Contents API, signs. -/
def notebookRunCell (path : String) (idx : Nat) : IO Json := do
  let fs := toFsPath path
  let nb ← readIpynb fs
  let cells := (nb.getObjVal? "cells" |>.toOption.bind (·.getArr?.toOption)).getD #[]
  if idx ≥ cells.size then
    throw <| IO.userError s!"cell_index {idx} out of range ({cells.size} cells)"
  let cell := cells[idx]!
  let source := sourceToString (cell.getObjVal? "source" |>.toOption.getD Json.null)
  -- Run.
  let result ← KernelBridge.execute source
  -- Build new outputs (split bundle-wise).
  let outputs : Array Json :=
    result.outputs.foldl (init := #[]) fun acc o => acc ++ outputToCells o
  -- Rebuild the cell with outputs + execution_count.
  let cellObj := cell.setObjVal! "outputs" (Json.arr outputs)
                     |>.setObjVal! "execution_count" (Json.num 1)
  let newCells := setCell cells idx cellObj
  let newNb := nb.setObjVal! "cells" (Json.arr newCells)
  -- Push via Contents API + sign.
  let xsrf ← fetchXsrf
  let api := toApiPath path
  putNotebook api newNb xsrf
  trustNotebook fs
  pure (Json.mkObj
    [ ("status", result.status)
    , ("outputs_written", Json.num outputs.size)
    , ("path", path)
    ])

/-- MCP tool: read a cell, execute its source on the live kernel,
    push outputs back to the notebook in a way the browser
    renders without a reload. -/
def tool_notebook_run_cell : ToolInfo × Handler :=
  let info : ToolInfo :=
    { name := "notebook_run_cell"
      description :=
        "Run the code in the given notebook cell against the live "
        ++ "xlean kernel and embed the kernel's outputs back into "
        ++ "the .ipynb so the user's browser tab refreshes the cell "
        ++ "in place — no manual reload needed.  Combines "
        ++ "`kernel_execute` (run code), Contents-API PUT (sync via "
        ++ "jupyter-collaboration), MIME-bundle splitting (so both "
        ++ "text logs and SVG renders show), and `jupyter trust` "
        ++ "(so SVG/HTML aren't quarantined as untrusted)."
      inputSchema := Json.mkObj
        [ ("type",       "object")
        , ("properties", Json.mkObj
            [ ("ipynb_path", Json.mkObj
                [ ("type",        "string")
                , ("description", "Workspace-relative or absolute path to the .ipynb.")
                ])
            , ("cell_index", Json.mkObj
                [ ("type",        "integer")
                , ("description", "0-based index of the cell whose source should be run.")
                ])
            ])
        , ("required",   Json.arr #["ipynb_path", "cell_index"])
        ]
    }
  let handler : Handler := fun params => do
    match params.getObjValAs? String "ipynb_path",
          params.getObjValAs? Nat "cell_index" with
    | .error _, _ => return .error (-32602, "Missing required parameter: ipynb_path")
    | _, .error _ => return .error (-32602, "Missing required parameter: cell_index")
    | .ok path, .ok idx =>
      try
        let res ← notebookRunCell path idx
        return .ok (textContent res.pretty)
      catch e =>
        return .error (-32000, s!"notebook_run_cell: {e.toString}")
  (info, handler)

end XLean.MCP
