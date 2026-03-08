import Qed

open Qed

def version : String := "0.1.0-dev"

/-- Status indicator for a verification result. -/
private def statusIndicator : VerificationResult → String
  | .pass _ => "PASS"
  | .fail _ => "FAIL"
  | .needsHuman _ => "NEEDS-HUMAN"
  | .skipped _ => "SKIP"

/-- Run single-pass verification on an already-loaded spec. -/
def verifySpec (spec : Spec) (jsonOutput : Bool) : IO UInt32 := do
  let results ← Verifier.verifyAll spec.criteria
  if jsonOutput then
    let json := Output.resultsToJson spec.name results
    IO.println (json.pretty 2)
  else
    IO.println s!"Verifying: {spec.name}"
    IO.println ""
    for (description, result) in results do
      IO.println s!"  [{statusIndicator result}] {description}"
    IO.println ""
    let failed := results.filter fun (_, result) => result.isFailed
    if failed.isEmpty then
      IO.println s!"All {results.length} criteria passed."
    else
      IO.eprintln s!"{failed.length} of {results.length} criteria failed."
  let anyFailed := results.any fun (_, result) => result.isFailed
  return if anyFailed then 1 else 0

/-- Load a spec file, handling IO exceptions (e.g., missing files). -/
def loadSpecSafe (path : String) : IO (Except String Spec) := do
  try
    SpecLoader.loadSpec path
  catch error =>
    return .error s!"cannot read '{path}': {error}"

/-- Load a spec and run single-pass verification. -/
def runVerify (path : String) (jsonOutput : Bool) : IO UInt32 := do
  match ← loadSpecSafe path with
  | .error message =>
    IO.eprintln s!"error: {message}"
    return 1
  | .ok spec => verifySpec spec jsonOutput

/-- Parse and validate a spec file, printing the parsed result. -/
def runParse (path : String) (jsonOutput : Bool) : IO UInt32 := do
  match ← loadSpecSafe path with
  | .error message =>
    IO.eprintln s!"error: {message}"
    return 1
  | .ok spec =>
    if jsonOutput then
      let modeStr := match spec.mode with
        | .verify => "verify"
        | .workerLoop _ _ => "workerLoop"
      IO.println (Lean.Json.mkObj [
        ("name", Lean.Json.str spec.name),
        ("mode", Lean.Json.str modeStr),
        ("criteriaCount", Lean.Json.num spec.criteria.length)
      ] |>.pretty 2)
    else
      IO.println s!"Spec: {spec.name}"
      IO.println s!"Mode: {repr spec.mode}"
      IO.println s!"Criteria: {spec.criteria.length}"
      for criterion in spec.criteria do
        IO.println s!"  - {criterion.description}"
    return 0

def printHelp : IO Unit := do
  IO.println "qed — typed spec-driven development with deterministic verification"
  IO.println ""
  IO.println "Usage:"
  IO.println "  qed run <spec-file>       Run verification (verify mode) or worker loop"
  IO.println "  qed verify <spec-file>    Single-pass verification (the CI command)"
  IO.println "  qed parse <spec-file>     Parse and validate a spec file"
  IO.println "  qed version               Print version"
  IO.println "  qed help                  Show this help"
  IO.println ""
  IO.println "Options:"
  IO.println "  --json                    Output results as JSON"

/-- Extract --json flag and remaining args from the argument list. -/
private def extractFlags (args : List String) : Bool × List String :=
  let jsonFlag := args.any (· == "--json")
  let remaining := args.filter (· != "--json")
  (jsonFlag, remaining)

def main (args : List String) : IO UInt32 := do
  let (jsonOutput, cleanArgs) := extractFlags args
  match cleanArgs with
  | ["version"] =>
    IO.println s!"qed {version}"
    return 0
  | ["help"] =>
    printHelp
    return 0
  | ["verify", path] =>
    runVerify path jsonOutput
  | ["run", path] =>
    match ← loadSpecSafe path with
    | .error message =>
      IO.eprintln s!"error: {message}"
      return 1
    | .ok spec =>
      match spec.mode with
      | .verify => verifySpec spec jsonOutput
      | .workerLoop _ _ =>
        IO.eprintln "Worker loop mode is not yet implemented."
        IO.eprintln "Use `qed verify` for single-pass verification."
        return 1
  | ["parse", path] =>
    runParse path jsonOutput
  | [] =>
    printHelp
    return 0
  | _ =>
    IO.eprintln s!"error: unknown command '{String.intercalate " " cleanArgs}'"
    IO.eprintln s!"Run `qed help` for usage information."
    return 1
