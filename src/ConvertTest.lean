/-
ConvertTest — pure-Lean tests for the Convert library.

Runnable as `lake exe convert-test`.  No external tooling, no
filesystem access; everything is in-memory string round-trips.
-/

import Convert

open Convert

private def assertEq {α : Type} [BEq α] [Repr α] (label : String) (a b : α) : IO Unit := do
  if a == b then
    IO.println s!"  PASS: {label}"
  else
    IO.eprintln s!"  FAIL: {label}"
    IO.eprintln s!"    expected: {repr b}"
    IO.eprintln s!"    actual:   {repr a}"

private def countMd (cells : Array Cell) : Nat :=
  cells.foldl (fun n c => if c.isMarkdown then n + 1 else n) 0

private def countCode (cells : Array Cell) : Nat :=
  cells.foldl (fun n c => if c.isCode then n + 1 else n) 0

unsafe def main : IO UInt32 := do
  IO.println "=== Convert library tests ==="

  -- 1. Empty document.
  do
    let cells := parseMarkdown ""
    assertEq "empty input → 0 cells" cells.size 0

  -- 2. Pure markdown, no fences.
  do
    let cells := parseMarkdown "# Title\n\nProse."
    assertEq "no-fence → 1 markdown cell" cells.size 1
    assertEq "no-fence → all markdown" (countCode cells) 0

  -- 3. Single lean fence.
  do
    let cells := parseMarkdown "Intro.\n\n```lean\ndef x := 1\n```\n\nOutro."
    assertEq "one fence → 3 cells (md/code/md)" cells.size 3
    assertEq "one fence → 1 code cell" (countCode cells) 1
    assertEq "one fence → 2 markdown cells" (countMd cells) 2

  -- 4. Non-lean fence stays in markdown.
  do
    let cells := parseMarkdown "Pre.\n\n```bash\necho hi\n```\n\nPost."
    assertEq "bash fence → 1 markdown cell" cells.size 1
    assertEq "bash fence → 0 code cells" (countCode cells) 0

  -- 5. Two lean fences.
  do
    let src :=
      "A\n\n```lean\ndef x := 1\n```\n\nB\n\n```lean\ndef y := 2\n```\n\nC"
    let cells := parseMarkdown src
    assertEq "two fences → 5 cells" cells.size 5
    assertEq "two fences → 2 code cells" (countCode cells) 2

  -- 6. Lean code is preserved verbatim (no `--` stripping).
  do
    let src := "```lean\ndef x : Nat := 42\n#eval x\n```"
    let cells := parseMarkdown src
    let code := cells.filter (·.isCode)
    assertEq "code cell count" code.size 1
    if code.size = 1 then
      let lines := code[0]!.lines
      assertEq "first line" (lines.getD 0 "") "def x : Nat := 42"
      assertEq "second line" (lines.getD 1 "") "#eval x"

  -- 7. ipynb JSON has the right top-level structure.
  do
    let cells := parseMarkdown "Hi\n\n```lean\nexample : True := trivial\n```"
    let json := cellsToIpynb cells
    let s := json.pretty 1
    assertEq "ipynb mentions kernelspec" (decide ((s.splitOn "kernelspec").length > 1)) true
    assertEq "ipynb mentions xeus-lean" (decide ((s.splitOn "xeus-lean").length > 1)) true
    assertEq "ipynb mentions cell_type" (decide ((s.splitOn "cell_type").length > 1)) true

  -- 8. lean:percent round-trip starts with the kernel header.
  do
    let cells := parseMarkdown "X\n\n```lean\ndef x := 1\n```"
    let s := cellsToPercent cells
    assertEq "percent header opens with -- ---"
      (s.startsWith "-- ---") true
    assertEq "percent body has -- %% code marker"
      (decide ((s.splitOn "-- %%\n").length > 1)) true
    assertEq "percent body has -- %% [markdown] marker"
      (decide ((s.splitOn "-- %% [markdown]\n").length > 1)) true

  IO.println "=== Done ==="
  return 0
