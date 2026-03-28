import Lean.Data.Json
import Qed.Types

set_option autoImplicit false

namespace Qed.Output

open Lean Qed

/-- Human-readable status indicator for display output (PASS/FAIL/etc). -/
def statusIndicator : VerificationResult → String
  | .pass _ => "PASS"
  | .fail _ => "FAIL"
  | .needsHuman _ => "NEEDS-HUMAN"
  | .skipped _ => "SKIP"

/-- ANSI escape codes for terminal colors. -/
def ansiReset : String := "\x1b[0m"
def ansiBold : String := "\x1b[1m"
def ansiGreen : String := "\x1b[32m"
def ansiRed : String := "\x1b[31m"
def ansiYellow : String := "\x1b[33m"
def ansiCyan : String := "\x1b[36m"
def ansiDim : String := "\x1b[2m"

/-- Status indicator with ANSI color for terminal display. -/
def colorStatusIndicator : VerificationResult → String
  | .pass _ => s!"{ansiGreen}PASS{ansiReset}"
  | .fail _ => s!"{ansiRed}FAIL{ansiReset}"
  | .needsHuman _ => s!"{ansiCyan}NEEDS-HUMAN{ansiReset}"
  | .skipped _ => s!"{ansiYellow}SKIP{ansiReset}"

/-- Compute the visible length of a string, ignoring ANSI escape sequences. -/
private partial def visibleLength (s : String) : Nat :=
  go s.toList 0 false
where
  go : List Char → Nat → Bool → Nat
    | [], count, _ => count
    | '\x1b' :: rest, count, _ => go rest count true
    | 'm' :: rest, count, true => go rest count false
    | _ :: rest, count, true => go rest count true
    | _ :: rest, count, false => go rest (count + 1) false

/-- Word-wrap text to fit within `width` visible characters.
    Splits on word boundaries only. Ignores ANSI escape sequences when
    measuring line length. -/
def wordWrap (text : String) (width : Nat) : List String :=
  if width < 20 then [text]
  else
    let words := text.splitOn " " |>.filter fun w => !w.isEmpty
    match words with
    | [] => []
    | first :: rest =>
      let (revLines, lastLine) := rest.foldl (init := ([], first)) fun (revLines, current) word =>
        if visibleLength current + 1 + visibleLength word > width then
          (current :: revLines, word)
        else
          (revLines, current ++ " " ++ word)
      (lastLine :: revLines).reverse

/-- Get the terminal width. Tries `stty size` via `/dev/tty` (works even when
    stdout is piped), falls back to `$COLUMNS`, then defaults to 80. -/
def getTerminalWidth : IO Nat := do
  let width ← try
    let result ← IO.Process.output {
      cmd := "sh"
      args := #["-c", "stty size </dev/tty 2>/dev/null"]
    }
    let parts := result.stdout.trimAscii.toString.splitOn " "
    match parts with
    | [_, columns] => pure (columns.toNat?.getD 0)
    | _ => pure 0
  catch _ => pure 0
  if width > 0 then return width
  match ← IO.getEnv "COLUMNS" with
  | some value => return value.toNat?.getD 80
  | none => return 80

/-- Print a line with word-wrapping. The first line starts with `firstPrefix`,
    continuation lines are indented to `continuationIndent` spaces to align
    with the text start. -/
def printWrapped (firstPrefix : String) (continuationIndent : Nat)
    (text : String) (termWidth : Nat) : IO Unit := do
  let wrapWidth := if termWidth > continuationIndent + 20 then termWidth - continuationIndent else 60
  let wrapped := wordWrap text wrapWidth
  match wrapped with
  | [] => IO.println firstPrefix
  | first :: rest =>
    IO.println s!"{firstPrefix}{first}"
    let pad := String.ofList (List.replicate continuationIndent ' ')
    for line in rest do
      IO.println s!"{pad}{line}"

/-- Serialize a VerificationResult to a JSON-friendly result string. -/
def resultStatus : VerificationResult → String
  | .pass _ => "passed"
  | .fail _ => "failed"
  | .needsHuman _ => "needs-human"
  | .skipped _ => "skipped"

/-- Extract the detail/message string from a VerificationResult. -/
def resultDetails : VerificationResult → String
  | .pass details => details
  | .fail details => details
  | .needsHuman instruction => instruction
  | .skipped reason => reason

/-- Serialize a single criterion execution to JSON with optional metadata fields.
    Includes `exitCode` and `elapsedMs` when present. -/
def executionToJson (description : String) (execution : CriterionExecution) : Json :=
  let base := [
    ("description", Json.str description),
    ("result", Json.str (resultStatus execution.result)),
    ("details", Json.str (resultDetails execution.result))
  ]
  let withExitCode := match execution.exitCode with
    | some code => base ++ [("exitCode", Json.num code.toNat)]
    | none => base
  let withElapsed := match execution.elapsedMs with
    | some ms => withExitCode ++ [("elapsedMs", Json.num ms)]
    | none => withExitCode
  let withIteration := match execution.iteration with
    | some n => withElapsed ++ [("iteration", Json.num n)]
    | none => withElapsed
  Json.mkObj withIteration

/-- Whether all executions passed (no failures). -/
def allExecutionsPassed (executions : List (String × CriterionExecution)) : Bool :=
  executions.all fun (_, execution) => !execution.isFailed

/-- Serialize all criterion executions with spec name and overall pass/fail. -/
def executionsToJson (specName : String) (executions : List (String × CriterionExecution)) : Json :=
  let criteriaJson := executions.map fun (description, execution) =>
    executionToJson description execution
  Json.mkObj [
    ("spec", Json.str specName),
    ("passed", Json.bool (allExecutionsPassed executions)),
    ("criteria", Json.arr criteriaJson.toArray)
  ]

/-- Serialize worker loop executions with spec name, state, and iteration history. -/
def workerExecutionsToJson (specName : String) (stateDescription : String)
    (executions : List (String × CriterionExecution)) : Json :=
  let criteriaJson := executions.map fun (description, execution) =>
    executionToJson description execution
  Json.mkObj [
    ("spec", Json.str specName),
    ("state", Json.str stateDescription),
    ("passed", Json.bool (allExecutionsPassed executions)),
    ("criteria", Json.arr criteriaJson.toArray)
  ]

/-- Extract `VerificationResult` from executions for use with existing functions
    that take `List (String × VerificationResult)` (e.g., text-mode display). -/
def extractResults (executions : List (String × CriterionExecution)) : List (String × VerificationResult) :=
  executions.map fun (description, execution) => (description, execution.result)

/-- Visible width of the status prefix `[STATUS] ` for a given result.
    Accounts for varying indicator lengths (PASS=4, NEEDS-HUMAN=11, etc.). -/
private def statusPrefixWidth (result : VerificationResult) : Nat :=
  1 + (statusIndicator result).length + 2  -- `[` + indicator + `]` + space

/-- Print a single verification result line with word wrapping.
    `baseIndent` is the leading space count (2 for top-level, 4 for nested). -/
def printResultLine (baseIndent : Nat) (description : String)
    (result : VerificationResult) (termWidth : Nat) : IO Unit := do
  let indent := String.ofList (List.replicate baseIndent ' ')
  let continuationIndent := baseIndent + statusPrefixWidth result
  let linePrefix := s!"{indent}[{colorStatusIndicator result}] "
  let text := match result with
    | .skipped reason => s!"{description} {ansiDim}— {reason}{ansiReset}"
    | _ => description
  printWrapped linePrefix continuationIndent text termWidth

/-- Print all verification results, returning (failedCount, skippedCount). -/
def printResultLines (baseIndent : Nat)
    (results : List (String × VerificationResult))
    (termWidth : Nat) : IO (Nat × Nat) := do
  let mut failedCount : Nat := 0
  let mut skippedCount : Nat := 0
  for (description, result) in results do
    printResultLine baseIndent description result termWidth
    if result.isFailed then failedCount := failedCount + 1
    if result.isSkipped then skippedCount := skippedCount + 1
  return (failedCount, skippedCount)

/-- Emit a single JSON line to stdout (compact, no pretty-printing).
    Used by `--json-lines` streaming mode. -/
def emitJsonLine (json : Json) : IO Unit :=
  IO.println (json.compress)

/-- Build a JSON Lines event with the given type and fields. -/
def jsonLineEvent (eventType : String) (fields : List (String × Json)) : Json :=
  Json.mkObj (("type", Json.str eventType) :: fields)

end Qed.Output
