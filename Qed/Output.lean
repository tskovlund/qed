import Lean.Data.Json
import Qed.Types

namespace Qed.Output

open Lean Qed

/-- Serialize a VerificationResult status to a JSON-friendly string. -/
private def resultStatus : VerificationResult → String
  | .pass _ => "pass"
  | .fail _ => "fail"
  | .needsHuman _ => "needs-human"
  | .skipped _ => "skipped"

/-- Extract the detail/message string from a VerificationResult. -/
private def resultDetails : VerificationResult → String
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

end Qed.Output
