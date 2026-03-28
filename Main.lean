import Qed

set_option autoImplicit false

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

/-- Report a structured error, using JSON format when --json is active. -/
private def reportError (error : ErrorInfo) (jsonOutput : Bool) : IO Unit := do
  if jsonOutput then
    IO.println (Error.formatErrorJson error |>.pretty 2)
  else
    IO.eprintln (Error.formatError error)

/-- Report a plain error message (convenience wrapper). -/
private def reportErrorMsg (message : String) (jsonOutput : Bool) : IO Unit :=
  reportError { message } jsonOutput

/-- Run single-pass verification and return the result as JSON with exit code.
    Used by both single-spec and multi-spec JSON output paths.
    Returns exit code 2 on integrity violation (with error JSON). -/
private def verifySpecJson (pinnedSpec : Spec.Pinned) (context : RunContext := .full)
    (pinned : Bool := false) : IO (UInt32 × Lean.Json) := do
  let spec := pinnedSpec.spec
  match ← Integrity.verify pinnedSpec pinned with
  | .error reason =>
    return (2, Error.formatErrorJson { message := s!"integrity violation: {reason}" })
  | .ok () => pure ()
  let criteria := filterBySchedule spec.criteria context
  let results ← Verifier.verifyAll criteria
  match ← Integrity.verify pinnedSpec pinned with
  | .error reason =>
    return (2, Error.formatErrorJson { message := s!"integrity violation: {reason}" })
  | .ok () => pure ()
  let passed := Output.allPassed results
  let json := Output.resultsToJson spec.name results
  return (if passed then 0 else 1, json)

/-- Run single-pass verification on an already-loaded spec.
    In text mode, results are streamed (displayed as each criterion completes)
    so human criteria prompts appear inline. -/
def verifySpec (pinnedSpec : Spec.Pinned) (jsonOutput : Bool) (context : RunContext := .full)
    (pinned : Bool := false) : IO UInt32 := do
  if jsonOutput then
    let (exitCode, json) ← verifySpecJson pinnedSpec context pinned
    IO.println (json.pretty 2)
    return exitCode
  let spec := pinnedSpec.spec
  -- Integrity check: before verification (hash + optional git pin)
  match ← Integrity.verify pinnedSpec pinned with
  | .error reason =>
    reportErrorMsg s!"integrity violation: {reason}" jsonOutput
    return 2
  | .ok () => pure ()
  let criteria := filterBySchedule spec.criteria context
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
  for criterion in criteria do
    let result ← Verifier.verifyCriterion criterion
    total := total + 1
    if result.isFailed then
      anyFailed := true
      failedCount := failedCount + 1
    if result.isSkipped then
      skippedCount := skippedCount + 1
    Output.printResultLine 2 criterion.description result termWidth
  -- Integrity check: after verification (catches verifier tampering)
  match ← Integrity.verify pinnedSpec pinned with
  | .error reason =>
    IO.eprintln ""
    reportErrorMsg s!"integrity violation: {reason}" jsonOutput
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

/-- Load a spec file, handling IO exceptions with human-readable messages. -/
def loadSpecSafe (path : String) : IO (Except ErrorInfo Spec.Pinned) := do
  if !(← System.FilePath.pathExists path) then
    let hint := if !path.endsWith ".spec.json" && !path.endsWith ".spec.toml" then
      some "spec files use .spec.json or .spec.toml extensions"
    else none
    return .error { message := s!"file not found: {path}", file := some path, hint }
  try
    SpecLoader.loadSpec path
  catch error =>
    return .error { message := s!"cannot read '{path}': {error}", file := some path }

/-- Load a spec and run single-pass verification. -/
def runVerify (path : String) (jsonOutput : Bool) (context : RunContext := .full)
    (pinned : Bool := false) : IO UInt32 := do
  match ← loadSpecSafe path with
  | .error info =>
    reportError info jsonOutput
    return 2
  | .ok pinnedSpec => verifySpec pinnedSpec jsonOutput context pinned

/-- Verify all specs in a directory. Returns 0 if all pass, 1 if any fail, 2 on error. -/
def runVerifyAll (directory : String) (jsonOutput : Bool) (context : RunContext := .full)
    (pinned : Bool := false) : IO UInt32 := do
  match ← SpecLoader.listAllSpecs directory with
  | .error message =>
    reportErrorMsg message jsonOutput
    return 2
  | .ok specs =>
    if specs.isEmpty then
      reportErrorMsg s!"no spec files found in '{directory}'" jsonOutput
      return 2
    if jsonOutput then
      -- JSON mode: collect all results into a single JSON object
      let mut specResults : Array Lean.Json := #[]
      let mut anyFailed := false
      for specPath in specs do
        match ← loadSpecSafe specPath.toString with
        | .error info =>
          reportError info jsonOutput
          return 2
        | .ok pinnedSpec =>
          let (exitCode, json) ← verifySpecJson pinnedSpec context pinned
          if exitCode == 2 then
            IO.println (json.pretty 2)
            return 2
          specResults := specResults.push json
          if exitCode == 1 then anyFailed := true
      IO.println (Lean.Json.mkObj [
        ("specs", Lean.Json.arr specResults),
        ("passed", Lean.Json.bool !anyFailed)
      ] |>.pretty 2)
      return if anyFailed then 1 else 0
    else
      -- Text mode: stream results as each spec completes
      let mut passedSpecs : Nat := 0
      let mut failedSpecs : Nat := 0
      for specPath in specs do
        let result ← runVerify specPath.toString jsonOutput context pinned
        if result == 1 then failedSpecs := failedSpecs + 1
        else if result == 0 then passedSpecs := passedSpecs + 1
        if result == 2 then return 2
        IO.println ""
      if specs.length > 1 then
        let total := passedSpecs + failedSpecs
        if failedSpecs == 0 then
          IO.println s!"{Output.ansiBold}{Output.ansiGreen}All {total} specs passed.{Output.ansiReset}"
        else
          IO.eprintln s!"{Output.ansiBold}{Output.ansiRed}{failedSpecs} of {total} specs failed.{Output.ansiReset}"
      return if failedSpecs > 0 then 1 else 0

/-- Parse and validate a spec file, printing the parsed result. -/
def runParse (path : String) (jsonOutput : Bool) : IO UInt32 := do
  match ← loadSpecSafe path with
  | .error info =>
    reportError info jsonOutput
    return 2
  | .ok pinnedSpec =>
    let spec := pinnedSpec.spec
    if jsonOutput then
      IO.println (Serializer.specToJson spec |>.pretty 2)
    else
      IO.println s!"Spec: {spec.name}"
      IO.println s!"Mode: {repr spec.mode}"
      IO.println s!"Criteria: {spec.criteria.length}"
      for criterion in spec.criteria do
        IO.println s!"  - {criterion.description}"
    return 0

/-- Generate or update the lock file from all specs in a directory. -/
def runLock (directory : String) (jsonOutput : Bool) : IO UInt32 := do
  match ← SpecLoader.listAllSpecs directory with
  | .error message =>
    reportErrorMsg message jsonOutput
    return 2
  | .ok specPaths =>
    if specPaths.isEmpty then
      reportErrorMsg s!"no spec files found in '{directory}'" jsonOutput
      return 2
    -- Load all specs
    let mut specs : List (String × Spec) := []
    for specPath in specPaths do
      match ← loadSpecSafe specPath.toString with
      | .error info =>
        reportError info jsonOutput
        return 2
      | .ok pinnedSpec =>
        specs := specs ++ [(specPath.toString, pinnedSpec.spec)]
    -- Generate lock file
    match ← ContractLock.generateLockFile specs with
    | .error info =>
      reportError info jsonOutput
      return 2
    | .ok lockFile =>
      ContractLock.writeLockFile lockFile
      let artifactCount := lockFile.specs.foldl (init := 0) fun count specLock =>
        count + specLock.criteria.foldl (init := 0) fun c criterionLock =>
          c + criterionLock.artifacts.length
      if jsonOutput then
        IO.println (ContractLock.lockFileToJson lockFile |>.pretty 2)
      else
        if artifactCount == 0 then
          IO.println "No lockable artifacts found."
        else
          IO.println s!"Locked {artifactCount} artifact(s) across {lockFile.specs.length} spec(s)."
          IO.println s!"Lock file written to {ContractLock.lockFilePath}"
      return 0

/-- Promote a worker loop spec to verify mode (strip worker section). -/
def runPromote (path : String) (output : Option String) (archive : Bool)
    (jsonOutput : Bool) : IO UInt32 := do
  match ← loadSpecSafe path with
  | .error info =>
    reportError info jsonOutput
    return 2
  | .ok pinnedSpec =>
    let spec := pinnedSpec.spec
    match spec.mode with
    | .verify =>
      reportErrorMsg s!"'{path}' is already in verify mode" jsonOutput
      return 2
    | .workerLoop _ _ =>
      if spec.criteria.isEmpty then
        reportErrorMsg s!"'{path}' has no criteria to promote" jsonOutput
        return 2
      let promoted : Spec := { spec with mode := .verify }
      let promotedJson := (Serializer.specToJson promoted).pretty 2
      match output with
      | some outputPath =>
        IO.FS.writeFile outputPath (promotedJson ++ "\n")
      | none =>
        IO.println promotedJson
      -- Archive the original if requested
      if archive then
        let archiveDir := (System.FilePath.mk path).parent.getD "." / "archive"
        let archivePath := archiveDir / ((System.FilePath.mk path).fileName.getD "spec")
        IO.FS.createDirAll archiveDir
        IO.FS.rename path archivePath
        if !jsonOutput then
          IO.println s!"Archived original → {archivePath}"
      -- Status output (only when --output redirects the spec to a file)
      match output with
      | some outputPath =>
        if jsonOutput then
          IO.println (Lean.Json.mkObj [
            ("status", Lean.Json.str "promoted"),
            ("specName", Lean.Json.str spec.name),
            ("outputPath", Lean.Json.str outputPath),
            ("archived", Lean.Json.bool archive)
          ] |>.pretty 2)
        else
          IO.println s!"Promoted '{spec.name}' to verify mode → {outputPath}"
      | none => pure ()
      return 0

def printHelp : IO Unit := do
  IO.println "qed — typed spec-driven development with deterministic verification"
  IO.println ""
  IO.println "Usage:"
  IO.println "  qed run <spec-file>       Run verification (verify mode) or worker loop"
  IO.println "  qed verify [spec-or-dir]  Verify a spec file, or all specs in a directory (recursive)"
  IO.println "                            Defaults to current directory if omitted"
  IO.println "  qed lock [directory]      Generate or update qed.lock from specs (defaults to current dir)"
  IO.println "  qed promote <spec-file>  Promote a worker loop spec to verify mode (strip worker section)"
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
  IO.println "  --no-lock                 Skip contract lock verification during worker loop"
  IO.println "  --output <path>           Output file for promote command"
  IO.println "  --archive                 Move original spec to archive/ after promoting"
  IO.println ""
  IO.println "Exit codes:"
  IO.println "  0  Success (all criteria passed)"
  IO.println "  1  Verification failure (one or more criteria failed)"
  IO.println "  2  Configuration or usage error (bad spec, missing file, unknown command)"

/-- Parsed CLI flags. -/
structure CliFlags where
  jsonOutput : Bool
  context : Option RunContext
  pinned : Bool
  noLock : Bool
  archive : Bool
  output : Option String
  cleanArgs : List String

/-- Extract --output <path> from args, returning the value and remaining args. -/
private def extractOutput (args : List String) : Option String × List String :=
  let rec go (remaining : List String) (acc : List String) : Option String × List String :=
    match remaining with
    | [] => (none, acc.reverse)
    | "--output" :: value :: rest => (some value, (acc.reverse ++ rest))
    | arg :: rest => go rest (arg :: acc)
  go args []

/-- Extract flags and remaining args from the argument list.
    Returns `none` for context when no explicit flag is given.
    Returns an error if conflicting mode flags are provided. -/
private def extractFlags (args : List String) : Except String CliFlags :=
  let jsonFlag := args.any (· == "--json")
  let pinFlag := args.any (· == "--pin")
  let noLockFlag := args.any (· == "--no-lock")
  let archiveFlag := args.any (· == "--archive")
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
    let filtered := args.filter fun a =>
      a != "--json" && a != "--auto" && a != "--extended" && a != "--full" &&
      a != "--pin" && a != "--no-lock" && a != "--archive"
    let (outputPath, remaining) := extractOutput filtered
    .ok { jsonOutput := jsonFlag, context, pinned := pinFlag,
          noLock := noLockFlag, archive := archiveFlag,
          output := outputPath, cleanArgs := remaining }

/-- Resolve the execution context: explicit flag > CI env var > full. -/
private def resolveContext (explicit : Option RunContext) : IO RunContext := do
  match explicit with
  | some ctx => return ctx
  | none =>
    let ciEnv ← IO.getEnv "CI"
    return if ciEnv == some "true" then .auto else .full

def main (args : List String) : IO UInt32 := do
  let flags ← match extractFlags args with
    | .ok result => pure result
    | .error message =>
      IO.eprintln s!"error: {message}"
      return 2
  let context ← resolveContext flags.context
  match flags.cleanArgs with
  | ["version"] =>
    IO.println s!"qed {version}"
    return 0
  | ["help"] =>
    printHelp
    return 0
  | ["lock"] =>
    runLock "." flags.jsonOutput
  | ["lock", directory] =>
    runLock directory flags.jsonOutput
  | ["promote", path] =>
    runPromote path flags.output flags.archive flags.jsonOutput
  | ["verify"] =>
    runVerifyAll "." flags.jsonOutput context flags.pinned
  | ["verify", path] =>
    let isDir ← (path : System.FilePath).isDir
    if isDir then runVerifyAll path flags.jsonOutput context flags.pinned
    else runVerify path flags.jsonOutput context flags.pinned
  | ["run", path] =>
    match ← loadSpecSafe path with
    | .error info =>
      reportError info flags.jsonOutput
      return 2
    | .ok pinnedSpec =>
      match pinnedSpec.spec.mode with
      | .verify => verifySpec pinnedSpec flags.jsonOutput context flags.pinned
      | .workerLoop worker loopConfig =>
        WorkerLoop.run pinnedSpec worker loopConfig flags.jsonOutput flags.pinned flags.noLock
  | ["parse", path] =>
    runParse path flags.jsonOutput
  | [] =>
    printHelp
    return 0
  | _ =>
    reportError { message := s!"unknown command '{String.intercalate " " flags.cleanArgs}'",
                  hint := some "run 'qed help' for usage information" } flags.jsonOutput
    return 2
