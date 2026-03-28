import Lean.Data.Json
import Qed.Types

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
    | [_, cols] => pure (cols.toNat?.getD 0)
    | _ => pure 0
  catch _ => pure 0
  if width > 0 then return width
  match ← IO.getEnv "COLUMNS" with
  | some val => return val.toNat?.getD 80
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

/-- Serialize a single verification result (description + result) to JSON. -/
def resultToJson (description : String) (result : VerificationResult) : Json :=
  Json.mkObj [
    ("description", Json.str description),
    ("result", Json.str (resultStatus result)),
    ("details", Json.str (resultDetails result))
  ]

/-- Whether all results passed (no failures). -/
def allPassed (results : List (String × VerificationResult)) : Bool :=
  results.all fun (_, result) => !result.isFailed

/-- Serialize all verification results with spec name and overall pass/fail. -/
def resultsToJson (specName : String) (results : List (String × VerificationResult)) : Json :=
  let criteriaJson := results.map fun (description, result) =>
    resultToJson description result
  Json.mkObj [
    ("spec", Json.str specName),
    ("passed", Json.bool (allPassed results)),
    ("criteria", Json.arr criteriaJson.toArray)
  ]

/-- Serialize worker loop results with spec name, state description, and overall pass/fail.
    Extends resultsToJson with a "state" field for worker loop context. -/
def workerResultsToJson (specName : String) (stateDescription : String)
    (results : List (String × VerificationResult)) : Json :=
  let criteriaJson := results.map fun (description, result) =>
    resultToJson description result
  Json.mkObj [
    ("spec", Json.str specName),
    ("state", Json.str stateDescription),
    ("passed", Json.bool (allPassed results)),
    ("criteria", Json.arr criteriaJson.toArray)
  ]

/-- Width of the status prefix `[XXXX] ` used for continuation indent alignment. -/
private def statusPrefixWidth : Nat := 7  -- `[` + 4-char status + `]` + space

/-- Print a single verification result line with word wrapping.
    `baseIndent` is the leading space count (2 for top-level, 4 for nested). -/
def printResultLine (baseIndent : Nat) (description : String)
    (result : VerificationResult) (termWidth : Nat) : IO Unit := do
  let indent := String.ofList (List.replicate baseIndent ' ')
  let continuationIndent := baseIndent + statusPrefixWidth
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

end Qed.Output
