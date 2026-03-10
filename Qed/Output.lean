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

/-- Serialize a VerificationResult status to a JSON-friendly string. -/
def resultStatus : VerificationResult → String
  | .pass _ => "pass"
  | .fail _ => "fail"
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
    ("status", Json.str (resultStatus result)),
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
