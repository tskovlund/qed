import Qed

open Qed

def version : String := "0.1.0-dev"

/-- Status indicator for a verification result. -/
private def statusIndicator : VerificationResult → String
  | .pass _ => "PASS"
  | .fail _ => "FAIL"
  | .needsHuman _ => "NEEDS-HUMAN"
  | .skipped _ => "SKIP"

/-- Extract the detail string from a VerificationResult. -/
private def resultDetails : VerificationResult → String
  | .pass details => details
  | .fail details => details
  | .needsHuman instruction => instruction
  | .skipped reason => reason

/-- Build the full prompt for a worker iteration, appending failure feedback. -/
private def buildPrompt (basePrompt : String)
    (failures : List (String × VerificationResult)) (iteration : Nat) : String :=
  if failures.isEmpty then
    basePrompt
  else
    let failureLines := failures.map fun (desc, result) =>
      s!"- {desc}: {resultDetails result}"
    basePrompt ++ s!"\n\n## Previous failures (iteration {iteration})\n\nThe following criteria failed. Fix these issues:\n\n" ++
      String.intercalate "\n" failureLines

/-- Write failures to a JSON file for Tier 2 workers. Returns the file path. -/
private def writeFailuresFile (failures : List (String × VerificationResult))
    (iteration : Nat) : IO String := do
  let path := s!"/tmp/qed-failures-{iteration}.json"
  let entries := failures.map fun (desc, result) =>
    Lean.Json.mkObj [
      ("description", Lean.Json.str desc),
      ("status", Lean.Json.str (statusIndicator result)),
      ("details", Lean.Json.str (resultDetails result))]
  let json := Lean.Json.arr entries.toArray
  IO.FS.writeFile path (json.pretty 2)
  return path

/-- The shell command and argument used to execute commands on this platform. -/
private def shellCmd : String × String :=
  if System.Platform.isWindows then ("cmd", "/c") else ("/bin/sh", "-c")

/-- Spawn a worker process with the appropriate env vars and prompt handling. -/
private def spawnWorker (worker : WorkerConfig)
    (failures : List (String × VerificationResult))
    (iteration : Nat) : IO (UInt32 × String × String) := do
  let failuresFile ← writeFailuresFile failures iteration
  let (cmd, flag) := shellCmd
  -- Build the shell command based on tier
  let shellCommand := match worker.prompt with
    | some basePrompt =>
      -- Tier 1: qed manages the prompt, passes via env var
      let fullPrompt := buildPrompt basePrompt failures iteration
      -- Set QED_PROMPT in the shell and append "$QED_PROMPT" to the command
      s!"export QED_PROMPT={shellQuote fullPrompt}; export QED_ITERATION={iteration}; export QED_FAILURES_FILE={shellQuote failuresFile}; {worker.command} \"$QED_PROMPT\""
    | none =>
      -- Tier 2: just set env vars, run command as-is
      s!"export QED_ITERATION={iteration}; export QED_FAILURES_FILE={shellQuote failuresFile}; {worker.command}"
  let result ← IO.Process.output {
    cmd := cmd
    args := #[flag, shellCommand]
    cwd := if worker.workdir == "." then none else some worker.workdir
  }
  return (result.exitCode, result.stdout, result.stderr)
where
  /-- Quote a string for shell use (single-quote wrapping with escape). -/
  shellQuote (s : String) : String :=
    "'" ++ s.replace "'" "'\\''" ++ "'"

/-- Run the worker loop: spawn worker, verify, feed failures back, repeat. -/
def runWorkerLoop (spec : Spec) (worker : WorkerConfig) (loopConfig : LoopConfig)
    (jsonOutput : Bool) : IO UInt32 := do
  let mut state : LoopState := .ready
  let mut context : StateMachine.LoopContext := StateMachine.LoopContext.initial
  let mut lastFailures : List (String × VerificationResult) := []
  let mut allResults : List (String × VerificationResult) := []
  -- Transition from ready to workerRunning
  let (newState, newContext) := StateMachine.transition loopConfig state context .workerDone
  state := newState
  context := newContext
  if !jsonOutput then
    IO.println s!"Worker loop: {spec.name}"
    IO.println s!"  max iterations: {loopConfig.maxIterations}, stuck threshold: {loopConfig.stuckThreshold}"
    IO.println ""
  while !state.isTerminal do
    match state with
    | .workerRunning iteration =>
      if !jsonOutput then
        IO.println s!"── Iteration {iteration} ──"
        IO.println "  Running worker..."
      let (exitCode, stdout, stderr) ← spawnWorker worker lastFailures iteration
      if !jsonOutput then
        if exitCode != 0 then
          IO.println s!"  Worker exited with code {exitCode}"
        else
          IO.println s!"  Worker completed (stdout: {stdout.length} chars)"
        if !stderr.isEmpty then
          IO.println s!"  Worker stderr: {stderr.trimAscii.take 200}"
      -- Worker done → transition to verifying
      let (s, c) := StateMachine.transition loopConfig state context .workerDone
      state := s
      context := c
    | .verifying _ =>
      if !jsonOutput then
        IO.println "  Verifying criteria..."
      let results ← Verifier.verifyAll spec.criteria
      allResults := results
      let failed := results.filter fun (_, result) => result.isFailed
      if !jsonOutput then
        for (description, result) in results do
          IO.println s!"    [{statusIndicator result}] {description}"
      if failed.isEmpty then
        let (s, c) := StateMachine.transition loopConfig state context .allPassed
        state := s
        context := c
      else
        lastFailures := failed
        let failureDescs := failed.map fun (desc, _) => desc
        let (s, c) := StateMachine.transition loopConfig state context (.someFailed failureDescs)
        state := s
        context := c
        if !jsonOutput && !state.isTerminal then
          IO.println s!"  {failed.length} criteria failed, retrying..."
          IO.println ""
    | _ => break  -- unreachable: while guard ensures non-terminal
  -- Output final result
  if jsonOutput then
    let stateStr := match state with
      | .passed iterations => s!"passed after {iterations} iterations"
      | .stuck iterations _ => s!"stuck after {iterations} iterations"
      | .maxIterationsReached iterations => s!"max iterations reached ({iterations})"
      | .escalated reason => s!"escalated: {reason}"
      | _ => "unknown"
    let resultJson := Lean.Json.mkObj [
      ("spec", Lean.Json.str spec.name),
      ("state", Lean.Json.str stateStr),
      ("passed", Lean.Json.bool (match state with | .passed _ => true | _ => false)),
      ("criteria", Lean.Json.arr (allResults.map fun (desc, result) =>
        Lean.Json.mkObj [
          ("description", Lean.Json.str desc),
          ("status", Lean.Json.str (statusIndicator result)),
          ("details", Lean.Json.str (resultDetails result))
        ]).toArray)]
    IO.println (resultJson.pretty 2)
  else
    IO.println ""
    match state with
    | .passed iterations =>
      IO.println s!"All criteria passed after {iterations} iteration(s)."
    | .stuck iterations failures =>
      IO.eprintln s!"Stuck after {iterations} iteration(s). Same failures for {loopConfig.stuckThreshold} consecutive iterations:"
      for f in failures do
        IO.eprintln s!"  - {f}"
    | .maxIterationsReached iterations =>
      IO.eprintln s!"Reached maximum iterations ({iterations})."
    | .escalated reason =>
      IO.eprintln s!"Escalated: {reason}"
    | _ => pure ()
  return match state with
    | .passed _ => 0
    | _ => 1

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

/-- Report an error, using JSON format when --json is active. -/
private def reportError (message : String) (jsonOutput : Bool) : IO Unit := do
  if jsonOutput then
    IO.println (Lean.Json.mkObj [
      ("error", Lean.Json.str message)
    ] |>.pretty 2)
  else
    IO.eprintln s!"error: {message}"

/-- Load a spec and run single-pass verification. -/
def runVerify (path : String) (jsonOutput : Bool) : IO UInt32 := do
  match ← loadSpecSafe path with
  | .error message =>
    reportError message jsonOutput
    return 1
  | .ok spec => verifySpec spec jsonOutput

/-- Parse and validate a spec file, printing the parsed result. -/
def runParse (path : String) (jsonOutput : Bool) : IO UInt32 := do
  match ← loadSpecSafe path with
  | .error message =>
    reportError message jsonOutput
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
      reportError message jsonOutput
      return 1
    | .ok spec =>
      match spec.mode with
      | .verify => verifySpec spec jsonOutput
      | .workerLoop worker loopConfig =>
        runWorkerLoop spec worker loopConfig jsonOutput
  | ["parse", path] =>
    runParse path jsonOutput
  | [] =>
    printHelp
    return 0
  | _ =>
    IO.eprintln s!"error: unknown command '{String.intercalate " " cleanArgs}'"
    IO.eprintln s!"Run `qed help` for usage information."
    return 1
