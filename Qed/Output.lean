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

/-- Word-wrap text to fit within `width` characters. Splits on word boundaries only. -/
def wordWrap (text : String) (width : Nat) : List String :=
  if width < 20 then [text]
  else
    let words := text.splitOn " " |>.filter fun w => !w.isEmpty
    match words with
    | [] => []
    | first :: rest =>
      let (revLines, lastLine) := rest.foldl (init := ([], first)) fun (revLines, current) word =>
        if current.length + 1 + word.length > width then
          (current :: revLines, word)
        else
          (revLines, current ++ " " ++ word)
      (lastLine :: revLines).reverse

/-- Get the terminal width, defaulting to 80 if detection fails. -/
def getTerminalWidth : IO Nat := do
  try
    let result ← IO.Process.output { cmd := "tput", args := #["cols"] }
    match result.stdout.trimAscii.toString.toNat? with
    | some w => return w
    | none => return 80
  catch _ => return 80

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

end Qed.Output
