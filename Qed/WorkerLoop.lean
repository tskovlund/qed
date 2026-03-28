import Lean.Data.Json
import Qed.Types
import Qed.Shell
import Qed.Agent
import Qed.StateMachine
import Qed.Verifier
import Qed.Output
import Qed.Error
import Qed.Integrity
import Qed.ContractLock

set_option autoImplicit false

namespace Qed.WorkerLoop

open Qed

/-- Maximum characters of stderr to preview in terminal output. -/
private def stderrPreviewLength : Nat := 200

/-- Thin wrapper around StateMachine.transition. The worker loop calls this
    exclusively — never StateMachine.transition directly. This lets us prove
    that the loop drives the proven state machine and nothing else. -/
def step (config : LoopConfig) (state : LoopState) (context : StateMachine.LoopContext)
    (event : StateMachine.LoopEvent) : LoopState × StateMachine.LoopContext :=
  StateMachine.transition config state context event

/-- Build the full prompt for a worker iteration, appending failure feedback. -/
def buildPrompt (basePrompt : String)
    (failures : List (String × VerificationResult)) (iteration : Nat) : String :=
  if failures.isEmpty then
    basePrompt
  else
    let failureLines := failures.map fun (desc, result) =>
      s!"- {desc}: {Output.resultDetails result}"
    basePrompt ++ s!"\n\n## Previous failures (iteration {iteration})\n\nThe following criteria failed. Fix these issues:\n\n" ++
      String.intercalate "\n" failureLines

/-- Get the temporary directory from $TMPDIR, falling back to /tmp. -/
private def getTmpDir : IO String := do
  match ← IO.getEnv "TMPDIR" with
  | some dir =>
      -- Strip trailing slashes for consistent path joining
      let trimmed := (dir.toSlice.dropEndWhile (· == '/')).toString
      return if trimmed.isEmpty then "/" else trimmed
  | none => return "/tmp"

/-- Write failures to a JSON file for Tier 2 workers. Returns the file path. -/
private def writeFailuresFile (failures : List (String × VerificationResult))
    (iteration : Nat) : IO String := do
  let pid ← IO.Process.getPID
  let tmpDir ← getTmpDir
  let path := s!"{tmpDir}/qed-failures-{pid}-{iteration}.json"
  let entries := failures.map fun (desc, result) =>
    Lean.Json.mkObj [
      ("description", Lean.Json.str desc),
      ("result", Lean.Json.str (Output.resultStatus result)),
      ("details", Lean.Json.str (Output.resultDetails result))]
  let json := Lean.Json.arr entries.toArray
  IO.FS.writeFile path (json.pretty 2)
  return path

/-- Re-export shellQuote for backward compatibility with proofs. -/
def shellQuote := Shell.shellQuote

/-- Spawn a worker process with the appropriate env vars and prompt handling.
    Catches non-UTF-8 output (Lean's IO.Process.output throws when the process
    emits bytes that aren't valid UTF-8). -/
def spawnWorker (worker : WorkerConfig)
    (failures : List (String × VerificationResult))
    (iteration : Nat) : IO Shell.TimeoutResult := do
  let failuresFile ← writeFailuresFile failures iteration
  let workerEnvVars := [
    (Agent.workerIterationVar, toString iteration),
    (Agent.workerFailuresFileVar, failuresFile)]
  -- Build the shell command based on tier
  let (envVars, command) := match worker.prompt with
    | some basePrompt =>
      -- Agent worker: qed manages the prompt, passes via env var
      let fullPrompt := buildPrompt basePrompt failures iteration
      ([(Agent.workerPromptVar, fullPrompt)] ++ workerEnvVars,
       worker.command.getD (Agent.defaultWorkerCommand worker.model))
    | none =>
      -- Script worker: run command as-is (parser ensures command is present)
      (workerEnvVars,
       worker.command.getD "true")
  let shellCommand := Shell.buildShellCommand envVars command
  let workdir := if worker.workdir == "." then none else some worker.workdir
  Shell.runShellCommandWithTimeout shellCommand worker.timeout workdir

/-- Run the worker loop: spawn worker, verify, feed failures back, repeat.
    Handles interruption (SIGINT) gracefully — Lean's runtime converts the
    signal into an IO exception, which we catch to report partial progress. -/
def run (pinnedSpec : Spec.Pinned) (worker : WorkerConfig) (loopConfig : LoopConfig)
    (jsonOutput : Bool) (pinned : Bool := false) (noLock : Bool := false) : IO UInt32 := do
  let spec := pinnedSpec.spec
  -- Load lock file once at loop start. This is intentional:
  -- 1. Avoids re-reading on every iteration (performance + TOCTOU safety)
  -- 2. The worker cannot bypass locks by regenerating qed.lock on disk —
  --    verification checks use the in-memory snapshot, not the file
  -- 3. New files created during the loop aren't part of the original contract
  let lockFile ← if noLock then pure none else
    try ContractLock.readLockFile
    catch error =>
      let errorInfo : ErrorInfo := { message := s!"{error}", hint := some "run 'qed lock' to regenerate" }
      if jsonOutput then
        IO.println (Error.formatErrorJson errorInfo |>.pretty 2)
      else
        IO.eprintln (Error.formatError errorInfo)
      return (2 : UInt32)
  let mut state : LoopState := .ready
  let mut context : StateMachine.LoopContext := StateMachine.LoopContext.initial
  let mut lastFailures : List (String × VerificationResult) := []
  let mut allResults : List (String × VerificationResult) := []
  -- Transition from ready to workerRunning. The event is irrelevant here:
  -- the state machine treats ready as a catch-all (| .ready, _ =>), so any
  -- event triggers the transition. We use .workerDone as a convention.
  let (newState, newContext) := step loopConfig state context .workerDone
  state := newState
  context := newContext
  if !jsonOutput then
    IO.println s!"{Output.ansiBold}Worker loop: {spec.name}{Output.ansiReset}"
    IO.println s!"  max iterations: {loopConfig.maxIterations}, stuck threshold: {loopConfig.stuckThreshold}"
    if lockFile.isSome then
      IO.println s!"  contract lock: {ContractLock.lockFilePath}"
    IO.println ""
  try
    while !state.isTerminal do
      match state with
      | .workerRunning iteration =>
        -- Integrity check: before spawning worker
        match ← Integrity.verify pinnedSpec pinned with
        | .error reason =>
          let (s, c) := step loopConfig state context (.integrityViolation reason)
          state := s; context := c; continue
        | .ok () => pure ()
        if !jsonOutput then
          IO.println s!"{Output.ansiBold}── Iteration {iteration} ──{Output.ansiReset}"
          IO.println "  Running worker..."
        let workerResult ← spawnWorker worker lastFailures iteration
        if !jsonOutput then
          match workerResult with
          | .timedOut _ stderr =>
            IO.println s!"  {Output.ansiRed}Worker timed out after {worker.timeout}s{Output.ansiReset}"
            if !stderr.isEmpty then
              IO.println s!"  Worker stderr: {stderr.trimAscii.take stderrPreviewLength}"
          | .completed exitCode stdout stderr =>
            if exitCode != 0 then
              IO.println s!"  {Output.ansiRed}Worker exited with code {exitCode}{Output.ansiReset}"
            else
              IO.println s!"  Worker completed (stdout: {stdout.length} chars)"
            if !stderr.isEmpty then
              IO.println s!"  Worker stderr: {stderr.trimAscii.take stderrPreviewLength}"
        -- Worker done → transition to verifying
        let (s, c) := step loopConfig state context .workerDone
        state := s
        context := c
      | .verifying _ =>
        -- Integrity check: before running verifiers
        match ← Integrity.verify pinnedSpec pinned with
        | .error reason =>
          let (s, c) := step loopConfig state context (.integrityViolation reason)
          state := s; context := c; continue
        | .ok () => pure ()
        -- Contract lock check: verify locked artifacts weren't modified by worker
        match lockFile with
        | some activeLockFile =>
          let violations ← ContractLock.verifyLocksForSpec activeLockFile pinnedSpec.path.toString
          if !violations.isEmpty then
            let reason := "contract lock violation: " ++ String.intercalate "; " violations
            let (s, c) := step loopConfig state context (.integrityViolation reason)
            state := s; context := c
            if !jsonOutput then
              IO.eprintln s!"  {Output.ansiRed}contract lock violated:{Output.ansiReset}"
              for violation in violations do
                IO.eprintln s!"    - {violation}"
            continue
        | none => pure ()
        if !jsonOutput then
          IO.println "  Verifying criteria..."
        let results ← Verifier.verifyAll spec.criteria
        allResults := results
        let failed := results.filter fun (_, result) => result.isFailed
        if !jsonOutput then
          let termWidth ← Output.getTerminalWidth
          let _ ← Output.printResultLines 4 results termWidth
        -- Integrity check: after running verifiers (catches verifier tampering)
        match ← Integrity.verify pinnedSpec pinned with
        | .error reason =>
          let (s, c) := step loopConfig state context (.integrityViolation reason)
          state := s; context := c; continue
        | .ok () => pure ()
        if failed.isEmpty then
          let (s, c) := step loopConfig state context .allPassed
          state := s
          context := c
        else
          lastFailures := failed
          let failureDescs := failed.map fun (desc, _) => desc
          let (s, c) := step loopConfig state context (.someFailed failureDescs)
          state := s
          context := c
          if !jsonOutput && !state.isTerminal then
            IO.println s!"  {failed.length} criteria failed, retrying..."
            IO.println ""
      | _ => break  -- unreachable: while guard ensures non-terminal
  catch error =>
    if jsonOutput then
      let errorJson := Lean.Json.mkObj [
        ("error", Lean.Json.str s!"interrupted: {error}"),
        ("state", Lean.Json.str (repr state).pretty)
      ]
      IO.println (errorJson.pretty 2)
    else
      IO.eprintln s!"\n{Output.ansiRed}error:{Output.ansiReset} interrupted: {error}"
      IO.eprintln s!"  state at interruption: {repr state}"
    return (1 : UInt32)
  -- Output final result
  if jsonOutput then
    let stateString := match state with
      | .passed iterations => s!"passed after {iterations} iterations"
      | .stuck iterations _ => s!"stuck after {iterations} iterations"
      | .maxIterationsReached iterations => s!"max iterations reached ({iterations})"
      | .escalated reason => s!"escalated: {reason}"
      | .integrityViolation reason => s!"integrity violation: {reason}"
      | _ => "unknown"
    let resultJson := Output.workerResultsToJson spec.name stateString allResults
    IO.println (resultJson.pretty 2)
  else
    IO.println ""
    match state with
    | .passed iterations =>
      IO.println s!"{Output.ansiGreen}All criteria passed after {iterations} iteration(s).{Output.ansiReset}"
    | .stuck iterations failures =>
      IO.eprintln s!"{Output.ansiRed}Stuck after {iterations} iteration(s). Same failures for {loopConfig.stuckThreshold} consecutive iterations:{Output.ansiReset}"
      for failure in failures do
        IO.eprintln s!"  - {failure}"
    | .maxIterationsReached iterations =>
      IO.eprintln s!"{Output.ansiRed}Reached maximum iterations ({iterations}).{Output.ansiReset}"
    | .escalated reason =>
      IO.eprintln s!"{Output.ansiRed}Escalated: {reason}{Output.ansiReset}"
    | .integrityViolation reason =>
      IO.eprintln s!"{Output.ansiRed}Integrity violation: {reason}{Output.ansiReset}"
    | _ => pure ()
  return match state with
    | .passed _ => 0
    | _ => 1

end Qed.WorkerLoop
