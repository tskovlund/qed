import Qed

open Qed

def version : String := "0.1.0-dev"

/-- Execution context for schedule filtering. -/
inductive RunContext where
  /-- No filtering — all criteria run. -/
  | full
  /-- Local hook (pre-push) — exclude `manual`, include `local`. -/
  | local
  /-- CI pipeline — exclude `manual` and `local`. -/
  | ci
  deriving BEq

/-- Filter criteria based on execution context and schedule. -/
def filterBySchedule (criteria : List AcceptanceCriterion) (context : RunContext) : List AcceptanceCriterion :=
  match context with
  | .full => criteria
  | .local => criteria.filter fun c => c.schedule != .manual
  | .ci => criteria.filter fun c => c.schedule == .always

/-- Run single-pass verification on an already-loaded spec.
    In text mode, results are streamed (displayed as each criterion completes)
    so human criteria prompts appear inline. -/
def verifySpec (spec : Spec) (jsonOutput : Bool) (context : RunContext := .full) : IO UInt32 := do
  let criteria := filterBySchedule spec.criteria context
  if jsonOutput then
    let results ← Verifier.verifyAll criteria
    let json := Output.resultsToJson spec.name results
    IO.println (json.pretty 2)
    let anyFailed := results.any fun (_, result) => result.isFailed
    return if anyFailed then 1 else 0
  else
    let termWidth ← Output.getTerminalWidth
    IO.println s!"{Output.ansiBold}Verifying: {spec.name}{Output.ansiReset}"
    IO.println ""
    if criteria.isEmpty then
      IO.println s!"  {Output.ansiDim}No criteria to verify in this context.{Output.ansiReset}"
      return 0
    let mut anyFailed := false
    let mut total : Nat := 0
    let mut failedCount : Nat := 0
    let mut skippedCount : Nat := 0
    -- Visible width of "  [XXXX] " prefix (2 + 1 + 4 + 1 + 1 = 9)
    let continuationIndent : Nat := 9
    for criterion in criteria do
      let result ← Verifier.verifyCriterion criterion
      total := total + 1
      if result.isFailed then
        anyFailed := true
        failedCount := failedCount + 1
      if result.isSkipped then
        skippedCount := skippedCount + 1
      let linePrefix := s!"  [{Output.colorStatusIndicator result}] "
      let text := match result with
        | .skipped reason => s!"{criterion.description} {Output.ansiDim}— {reason}{Output.ansiReset}"
        | _ => criterion.description
      Output.printWrapped linePrefix continuationIndent text termWidth
    IO.println ""
    if failedCount == 0 then
      if skippedCount == total then
        IO.println s!"{Output.ansiYellow}All {total} criteria skipped.{Output.ansiReset}"
      else
        let skippedNote := if skippedCount > 0 then s!" ({skippedCount} skipped)" else ""
        IO.println s!"{Output.ansiGreen}All {total - skippedCount} criteria passed.{Output.ansiReset}{skippedNote}"
    else
      IO.eprintln s!"{Output.ansiRed}{failedCount} of {total} criteria failed.{Output.ansiReset}"
    return if anyFailed then 1 else 0

/-- Load a spec file, handling IO exceptions (e.g., missing files). -/
def loadSpecSafe (path : String) : IO (Except String Spec) := do
  try
    SpecLoader.loadSpec path
  catch error =>
    return .error s!"cannot read '{path}': {error}"

/-- Report an error, using JSON format when --json is active. -/
private def reportError (message : String) (jsonOutput : Bool) : IO Unit := do
  if jsonOutput then
    IO.println (Lean.Json.mkObj [
      ("error", Lean.Json.str message)
    ] |>.pretty 2)
  else
    IO.eprintln s!"error: {message}"

/-- Load a spec and run single-pass verification. -/
def runVerify (path : String) (jsonOutput : Bool) (context : RunContext := .full) : IO UInt32 := do
  match ← loadSpecSafe path with
  | .error message =>
    reportError message jsonOutput
    return 2
  | .ok spec => verifySpec spec jsonOutput context

/-- Verify all specs in a directory. Returns 0 if all pass, 1 if any fail, 2 on error. -/
def runVerifyAll (directory : String) (jsonOutput : Bool) (context : RunContext := .full) : IO UInt32 := do
  match ← SpecLoader.listAllSpecs directory with
  | .error message =>
    reportError message jsonOutput
    return 2
  | .ok specs =>
    if specs.isEmpty then
      reportError s!"no spec files found in '{directory}'" jsonOutput
      return 2
    let mut passedSpecs : Nat := 0
    let mut failedSpecs : Nat := 0
    for specPath in specs do
      let result ← runVerify specPath.toString jsonOutput context
      if result == 1 then failedSpecs := failedSpecs + 1
      else if result == 0 then passedSpecs := passedSpecs + 1
      if result == 2 then return 2
      if !jsonOutput then IO.println ""
    if !jsonOutput && specs.length > 1 then
      let total := passedSpecs + failedSpecs
      if failedSpecs == 0 then
        IO.println s!"{Output.ansiBold}{Output.ansiGreen}All {total} specs passed.{Output.ansiReset}"
      else
        IO.eprintln s!"{Output.ansiBold}{Output.ansiRed}{failedSpecs} of {total} specs failed.{Output.ansiReset}"
    return if failedSpecs > 0 then 1 else 0

/-- Parse and validate a spec file, printing the parsed result. -/
def runParse (path : String) (jsonOutput : Bool) : IO UInt32 := do
  match ← loadSpecSafe path with
  | .error message =>
    reportError message jsonOutput
    return 2
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
  IO.println "  qed verify [spec-or-dir]  Verify a spec file, or all specs in a directory (recursive)"
  IO.println "                            Defaults to current directory if omitted"
  IO.println "  qed parse <spec-file>     Parse and validate a spec file"
  IO.println "  qed version               Print version"
  IO.println "  qed help                  Show this help"
  IO.println ""
  IO.println "Options:"
  IO.println "  --json                    Output results as JSON"
  IO.println "  --local                   Local mode — exclude schedule = \"manual\" criteria"
  IO.println "  --ci                      CI mode — exclude schedule = \"manual\" and \"local\" criteria"
  IO.println ""
  IO.println "Exit codes:"
  IO.println "  0  Success (all criteria passed)"
  IO.println "  1  Verification failure (one or more criteria failed)"
  IO.println "  2  Configuration or usage error (bad spec, missing file, unknown command)"

/-- Extract flags and remaining args from the argument list. -/
private def extractFlags (args : List String) : Bool × RunContext × List String :=
  let jsonFlag := args.any (· == "--json")
  let context := if args.any (· == "--ci") then RunContext.ci
    else if args.any (· == "--local") then RunContext.local
    else RunContext.full
  let remaining := args.filter fun a => a != "--json" && a != "--ci" && a != "--local"
  (jsonFlag, context, remaining)

def main (args : List String) : IO UInt32 := do
  let (jsonOutput, context, cleanArgs) := extractFlags args
  match cleanArgs with
  | ["version"] =>
    IO.println s!"qed {version}"
    return 0
  | ["help"] =>
    printHelp
    return 0
  | ["verify"] =>
    runVerifyAll "." jsonOutput context
  | ["verify", path] =>
    let isDir ← (path : System.FilePath).isDir
    if isDir then runVerifyAll path jsonOutput context
    else runVerify path jsonOutput context
  | ["run", path] =>
    match ← loadSpecSafe path with
    | .error message =>
      reportError message jsonOutput
      return 2
    | .ok spec =>
      match spec.mode with
      | .verify => verifySpec spec jsonOutput context
      | .workerLoop worker loopConfig =>
        WorkerLoop.run spec worker loopConfig jsonOutput
  | ["parse", path] =>
    runParse path jsonOutput
  | [] =>
    printHelp
    return 0
  | _ =>
    IO.eprintln s!"error: unknown command '{String.intercalate " " cleanArgs}'"
    IO.eprintln s!"Run `qed help` for usage information."
    return 2
