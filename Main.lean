import Qed

open Qed

def version : String := "0.1.0-dev"

/-- Execution context for schedule filtering.
    Forms a hierarchy: full ⊃ extended ⊃ auto. -/
inductive RunContext where
  /-- No filtering — all criteria run (including manual). -/
  | full
  /-- Extended — include heavy criteria, exclude manual. For thorough CI runs. -/
  | extended
  /-- Automated mode — exclude heavy and manual criteria. For CI, hooks, scripts. -/
  | auto
  deriving BEq

/-- Filter criteria based on execution context and schedule. -/
def filterBySchedule (criteria : List AcceptanceCriterion) (context : RunContext) : List AcceptanceCriterion :=
  match context with
  | .full => criteria
  | .extended => criteria.filter fun c => c.schedule != .manual
  | .auto => criteria.filter fun c => c.schedule == .always

/-- Report an error, using JSON format when --json is active. -/
private def reportError (message : String) (jsonOutput : Bool) : IO Unit := do
  if jsonOutput then
    IO.println (Lean.Json.mkObj [
      ("error", Lean.Json.str message)
    ] |>.pretty 2)
  else
    IO.eprintln s!"error: {message}"

/-- Run single-pass verification on an already-loaded spec.
    In text mode, results are streamed (displayed as each criterion completes)
    so human criteria prompts appear inline. -/
def verifySpec (pinnedSpec : Spec.Pinned) (jsonOutput : Bool) (context : RunContext := .full)
    (pinned : Bool := false) : IO UInt32 := do
  let spec := pinnedSpec.spec
  -- Integrity check: before verification (hash + optional git pin)
  match ← Integrity.verify pinnedSpec pinned with
  | .error reason =>
    reportError s!"integrity violation: {reason}" jsonOutput
    return 2
  | .ok () => pure ()
  let criteria := filterBySchedule spec.criteria context
  if jsonOutput then
    let results ← Verifier.verifyAll criteria
    -- Integrity check: after verification (catches verifier tampering)
    match ← Integrity.verify pinnedSpec pinned with
    | .error reason =>
      reportError s!"integrity violation: {reason}" jsonOutput
      return 2
    | .ok () => pure ()
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
    -- Integrity check: after verification (catches verifier tampering)
    match ← Integrity.verify pinnedSpec pinned with
    | .error reason =>
      IO.eprintln ""
      reportError s!"integrity violation: {reason}" jsonOutput
      return 2
    | .ok () => pure ()
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
def loadSpecSafe (path : String) : IO (Except String Spec.Pinned) := do
  try
    SpecLoader.loadSpec path
  catch error =>
    return .error s!"cannot read '{path}': {error}"

/-- Load a spec and run single-pass verification. -/
def runVerify (path : String) (jsonOutput : Bool) (context : RunContext := .full)
    (pinned : Bool := false) : IO UInt32 := do
  match ← loadSpecSafe path with
  | .error message =>
    reportError message jsonOutput
    return 2
  | .ok pinnedSpec => verifySpec pinnedSpec jsonOutput context pinned

/-- Verify all specs in a directory. Returns 0 if all pass, 1 if any fail, 2 on error. -/
def runVerifyAll (directory : String) (jsonOutput : Bool) (context : RunContext := .full)
    (pinned : Bool := false) : IO UInt32 := do
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
      let result ← runVerify specPath.toString jsonOutput context pinned
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
  | .ok pinnedSpec =>
    let spec := pinnedSpec.spec
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
  IO.println "  --auto                    Skip heavy and manual criteria (auto-detected when CI=true)"
  IO.println "  --extended                Include heavy criteria, skip manual (for thorough CI runs)"
  IO.println "  --full                    Run all criteria including manual (overrides CI auto-detection)"
  IO.println "  --pin                     Require spec files to match their git-committed version"
  IO.println ""
  IO.println "Exit codes:"
  IO.println "  0  Success (all criteria passed)"
  IO.println "  1  Verification failure (one or more criteria failed)"
  IO.println "  2  Configuration or usage error (bad spec, missing file, unknown command)"

/-- Extract flags and remaining args from the argument list.
    Returns `none` for context when no explicit flag is given.
    Returns an error if conflicting mode flags are provided. -/
private def extractFlags (args : List String)
    : Except String (Bool × Option RunContext × Bool × List String) :=
  let jsonFlag := args.any (· == "--json")
  let pinFlag := args.any (· == "--pin")
  let hasAuto := args.any (· == "--auto")
  let hasExtended := args.any (· == "--extended")
  let hasFull := args.any (· == "--full")
  let modeCount := (if hasAuto then 1 else 0) + (if hasExtended then 1 else 0) +
    (if hasFull then 1 else 0)
  if modeCount > 1 then
    .error "conflicting flags: use only one of --auto, --extended, or --full"
  else
    let context := if hasAuto then some RunContext.auto
      else if hasExtended then some RunContext.extended
      else if hasFull then some RunContext.full
      else none
    let remaining := args.filter fun a =>
      a != "--json" && a != "--auto" && a != "--extended" && a != "--full" && a != "--pin"
    .ok (jsonFlag, context, pinFlag, remaining)

/-- Resolve the execution context: explicit flag > CI env var > full. -/
private def resolveContext (explicit : Option RunContext) : IO RunContext := do
  match explicit with
  | some ctx => return ctx
  | none =>
    let ciEnv ← IO.getEnv "CI"
    return if ciEnv == some "true" then .auto else .full

def main (args : List String) : IO UInt32 := do
  let (jsonOutput, explicitContext, pinned, cleanArgs) ← match extractFlags args with
    | .ok result => pure result
    | .error message =>
      IO.eprintln s!"error: {message}"
      return 2
  let context ← resolveContext explicitContext
  match cleanArgs with
  | ["version"] =>
    IO.println s!"qed {version}"
    return 0
  | ["help"] =>
    printHelp
    return 0
  | ["verify"] =>
    runVerifyAll "." jsonOutput context pinned
  | ["verify", path] =>
    let isDir ← (path : System.FilePath).isDir
    if isDir then runVerifyAll path jsonOutput context pinned
    else runVerify path jsonOutput context pinned
  | ["run", path] =>
    match ← loadSpecSafe path with
    | .error message =>
      reportError message jsonOutput
      return 2
    | .ok pinnedSpec =>
      match pinnedSpec.spec.mode with
      | .verify => verifySpec pinnedSpec jsonOutput context pinned
      | .workerLoop worker loopConfig =>
        WorkerLoop.run pinnedSpec worker loopConfig jsonOutput pinned
  | ["parse", path] =>
    runParse path jsonOutput
  | [] =>
    printHelp
    return 0
  | _ =>
    IO.eprintln s!"error: unknown command '{String.intercalate " " cleanArgs}'"
    IO.eprintln s!"Run `qed help` for usage information."
    return 2
