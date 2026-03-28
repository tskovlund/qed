import Lean.Data.Json
import Qed.Types
import Qed.Shell

set_option autoImplicit false

namespace Qed.Output

open Lean Qed

-- ============================================================================
-- Primitives: ANSI codes, status indicators, text wrapping
-- ============================================================================

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

/-- Maximum characters of stderr to preview in terminal output. -/
def stderrPreviewLength : Nat := 200

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

-- ============================================================================
-- JSON serialization
-- ============================================================================

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
    ("type", Json.str "criterion"),
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

/-- Emit a single JSON line to stdout (compact, no pretty-printing).
    Used by `--json-lines` streaming mode. -/
def emitJsonLine (json : Json) : IO Unit :=
  IO.println (json.compress)

/-- Build a JSON Lines event with the given type and fields. -/
def jsonLineEvent (eventType : String) (fields : List (String × Json)) : Json :=
  Json.mkObj (("type", Json.str eventType) :: fields)

-- ============================================================================
-- Text-mode printing helpers
-- ============================================================================

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

-- ============================================================================
-- Format-dispatched emit functions: verify mode
-- ============================================================================

/-- Emit verify mode header. Text prints the spec name, JSON Lines emits
    a `spec_start` event, JSON is a no-op (output is batched). -/
def emitVerifyHeader (format : OutputFormat) (specName : String)
    (criteriaCount : Nat) : IO Unit := do
  match format with
  | .jsonLines =>
    emitJsonLine (jsonLineEvent "spec_start"
      [("spec", Json.str specName),
       ("criteriaCount", Json.num criteriaCount)])
  | .text =>
    IO.println s!"{ansiBold}Verifying: {specName}{ansiReset}"
    IO.println ""
  | .json => pure ()

/-- Emit a single criterion result. Text prints the status line, JSON Lines
    emits the criterion event, JSON is a no-op (results are batched). -/
def emitCriterionResult (format : OutputFormat) (indent : Nat)
    (description : String) (execution : CriterionExecution) : IO Unit := do
  match format with
  | .jsonLines => emitJsonLine (executionToJson description execution)
  | .text =>
    let termWidth ← getTerminalWidth
    printResultLine indent description execution.result termWidth
  | .json => pure ()

/-- Emit all criterion results for a batch (worker loop iterations). -/
def emitCriteriaResults (format : OutputFormat) (indent : Nat)
    (executions : List (String × CriterionExecution)) : IO Unit := do
  match format with
  | .jsonLines =>
    for (description, execution) in executions do
      emitJsonLine (executionToJson description execution)
  | .text =>
    let termWidth ← getTerminalWidth
    let results := extractResults executions
    let _ ← printResultLines indent results termWidth
  | .json => pure ()

/-- Emit verify mode completion summary. -/
def emitVerifyDone (format : OutputFormat) (specName : String)
    (anyFailed : Bool) (failedCount : Nat) (skippedCount : Nat)
    (total : Nat) : IO Unit := do
  match format with
  | .jsonLines =>
    emitJsonLine (jsonLineEvent "spec_done"
      [("spec", Json.str specName),
       ("passed", Json.bool !anyFailed)])
  | .text =>
    IO.println ""
    if failedCount == 0 then
      if skippedCount == total then
        IO.println s!"{ansiYellow}All {total} criteria skipped.{ansiReset}"
      else
        let skippedNote := if skippedCount > 0 then s!" ({skippedCount} skipped)" else ""
        IO.println s!"{ansiGreen}All {total - skippedCount} criteria passed.{ansiReset}{skippedNote}"
    else
      IO.eprintln s!"{ansiRed}{failedCount} of {total} criteria failed.{ansiReset}"
  | .json => pure ()

-- ============================================================================
-- Format-dispatched emit functions: worker loop
-- ============================================================================

/-- Emit worker loop header: spec name, config, lock status. -/
def emitLoopHeader (format : OutputFormat) (specName : String)
    (maxIterations : Nat) (stuckThreshold : Nat)
    (lockFilePath : Option String) : IO Unit := do
  match format with
  | .jsonLines =>
    emitJsonLine (jsonLineEvent "spec_start"
      [("spec", Json.str specName),
       ("mode", Json.str "worker_loop"),
       ("maxIterations", Json.num maxIterations),
       ("stuckThreshold", Json.num stuckThreshold)])
  | .text =>
    IO.println s!"{ansiBold}Worker loop: {specName}{ansiReset}"
    IO.println s!"  max iterations: {maxIterations}, stuck threshold: {stuckThreshold}"
    match lockFilePath with
    | some path => IO.println s!"  contract lock: {path}"
    | none => pure ()
    IO.println ""
  | .json => pure ()

/-- Emit iteration start marker. -/
def emitIterationStart (format : OutputFormat) (iteration : Nat) : IO Unit := do
  match format with
  | .jsonLines =>
    emitJsonLine (jsonLineEvent "iteration_start"
      [("iteration", Json.num iteration)])
  | .text =>
    IO.println s!"{ansiBold}── Iteration {iteration} ──{ansiReset}"
    IO.println "  Running worker..."
  | .json => pure ()

/-- Emit worker completion result with timing and exit info. -/
def emitWorkerResult (format : OutputFormat) (iteration : Nat)
    (workerResult : Shell.TimeoutResult) (workerTimeout : Nat) : IO Unit := do
  match format with
  | .jsonLines =>
    match workerResult with
    | .timedOut _ _ elapsedMs =>
      emitJsonLine (jsonLineEvent "worker_done"
        [("iteration", Json.num iteration),
         ("timedOut", Json.bool true),
         ("elapsedMs", Json.num elapsedMs)])
    | .completed exitCode _ _ elapsedMs =>
      emitJsonLine (jsonLineEvent "worker_done"
        [("iteration", Json.num iteration),
         ("exitCode", Json.num exitCode.toNat),
         ("elapsedMs", Json.num elapsedMs)])
  | .text =>
    match workerResult with
    | .timedOut _ stderr _ =>
      IO.println s!"  {ansiRed}Worker timed out after {workerTimeout}s{ansiReset}"
      if !stderr.isEmpty then
        IO.println s!"  Worker stderr: {stderr.trimAscii.take stderrPreviewLength}"
    | .completed exitCode stdout stderr _ =>
      if exitCode != 0 then
        IO.println s!"  {ansiRed}Worker exited with code {exitCode}{ansiReset}"
      else
        IO.println s!"  Worker completed (stdout: {stdout.length} chars)"
      if !stderr.isEmpty then
        IO.println s!"  Worker stderr: {stderr.trimAscii.take stderrPreviewLength}"
  | .json => pure ()

/-- Emit "Verifying criteria..." in text mode. -/
def emitVerifyingCriteria (format : OutputFormat) : IO Unit :=
  if format == .text then IO.println "  Verifying criteria..." else pure ()

/-- Emit iteration done summary. -/
def emitIterationDone (format : OutputFormat) (iteration : Nat)
    (passed : Bool) (failedCount : Nat) (isTerminal : Bool) : IO Unit := do
  match format with
  | .jsonLines =>
    emitJsonLine (jsonLineEvent "iteration_done"
      [("iteration", Json.num iteration),
       ("passed", Json.bool passed),
       ("failedCount", Json.num failedCount)])
  | .text =>
    if !passed && !isTerminal then
      IO.println s!"  {failedCount} criteria failed, retrying..."
      IO.println ""
  | .json => pure ()

/-- Emit contract lock violation message. -/
def emitContractViolation (format : OutputFormat)
    (violations : List String) : IO Unit := do
  if format == .text then
    IO.eprintln s!"  {ansiRed}contract lock violated:{ansiReset}"
    for violation in violations do
      IO.eprintln s!"    - {violation}"

/-- Emit worker loop error (interruption). -/
def emitLoopError (format : OutputFormat) (errorMessage : String)
    (stateRepr : String) : IO Unit := do
  match format with
  | .jsonLines =>
    emitJsonLine (jsonLineEvent "error"
      [("message", Json.str errorMessage)])
  | .json =>
    let errorJson := Json.mkObj [
      ("error", Json.str errorMessage),
      ("state", Json.str stateRepr)
    ]
    IO.println (errorJson.pretty 2)
  | .text =>
    IO.eprintln s!"\n{ansiRed}error:{ansiReset} {errorMessage}"
    IO.eprintln s!"  state at interruption: {stateRepr}"

/-- Emit worker loop final result. -/
def emitLoopResult (format : OutputFormat) (specName : String)
    (state : LoopState) (stuckThreshold : Nat)
    (allExecutions : List (String × CriterionExecution)) : IO Unit := do
  let stateString := match state with
    | .passed iterations => s!"passed after {iterations} iterations"
    | .stuck iterations _ => s!"stuck after {iterations} iterations"
    | .maxIterationsReached iterations => s!"max iterations reached ({iterations})"
    | .escalated reason => s!"escalated: {reason}"
    | .integrityViolation reason => s!"integrity violation: {reason}"
    | _ => "unknown"
  match format with
  | .jsonLines =>
    let passed := match state with | .passed _ => true | _ => false
    emitJsonLine (jsonLineEvent "loop_done"
      [("spec", Json.str specName),
       ("state", Json.str stateString),
       ("passed", Json.bool passed)])
  | .json =>
    let resultJson := workerExecutionsToJson specName stateString allExecutions
    IO.println (resultJson.pretty 2)
  | .text =>
    IO.println ""
    match state with
    | .passed iterations =>
      IO.println s!"{ansiGreen}All criteria passed after {iterations} iteration(s).{ansiReset}"
    | .stuck iterations failures =>
      IO.eprintln s!"{ansiRed}Stuck after {iterations} iteration(s). Same failures for {stuckThreshold} consecutive iterations:{ansiReset}"
      for failure in failures do
        IO.eprintln s!"  - {failure}"
    | .maxIterationsReached iterations =>
      IO.eprintln s!"{ansiRed}Reached maximum iterations ({iterations}).{ansiReset}"
    | .escalated reason =>
      IO.eprintln s!"{ansiRed}Escalated: {reason}{ansiReset}"
    | .integrityViolation reason =>
      IO.eprintln s!"{ansiRed}Integrity violation: {reason}{ansiReset}"
    | _ => pure ()

end Qed.Output
