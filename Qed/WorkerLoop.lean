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
    (format : OutputFormat) (pinned : Bool := false)
    (noLock : Bool := false) : IO UInt32 := do
  let spec := pinnedSpec.spec
  -- Load lock file once at loop start. This is intentional:
  -- 1. Avoids re-reading on every iteration (performance + TOCTOU safety)
  -- 2. The worker cannot bypass locks by regenerating qed.lock on disk —
  --    verification checks use the in-memory snapshot, not the file
  -- 3. New files created during the loop aren't part of the original contract
  let lockFile ← if noLock then pure none else
    try ContractLock.readLockFile
    catch error =>
      Error.reportError format { message := s!"{error}", hint := some "run 'qed lock' to regenerate" }
      return (2 : UInt32)
  let mut state : LoopState := .ready
  let mut context : StateMachine.LoopContext := StateMachine.LoopContext.initial
  let mut lastFailures : List (String × VerificationResult) := []
  let mut allExecutions : List (String × CriterionExecution) := []
  -- Transition from ready to workerRunning. The event is irrelevant here:
  -- the state machine treats ready as a catch-all (| .ready, _ =>), so any
  -- event triggers the transition. We use .workerDone as a convention.
  let (newState, newContext) := step loopConfig state context .workerDone
  state := newState
  context := newContext
  let lockPath := if lockFile.isSome then some ContractLock.lockFilePath.toString else none
  Output.emitLoopHeader format spec.name loopConfig.maxIterations loopConfig.stuckThreshold lockPath
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
        Output.emitIterationStart format iteration
        let workerResult ← spawnWorker worker lastFailures iteration
        Output.emitWorkerResult format iteration workerResult worker.timeout
        -- Worker done → transition to verifying
        let (s, c) := step loopConfig state context .workerDone
        state := s
        context := c
      | .verifying iteration =>
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
            Output.emitContractViolation format violations
            continue
        | none => pure ()
        Output.emitVerifyingCriteria format
        let executions ← Verifier.verifyAll spec.criteria
        -- Stamp iteration number on each execution
        let executions := executions.map fun (description, execution) =>
          (description, { execution with iteration := some iteration })
        allExecutions := executions
        Output.emitCriteriaResults format 4 executions
        let results := Output.extractResults executions
        let failed := results.filter fun (_, result) => result.isFailed
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
          Output.emitIterationDone format iteration true 0 false
        else
          lastFailures := failed
          let failureDescs := failed.map fun (desc, _) => desc
          let (s, c) := step loopConfig state context (.someFailed failureDescs)
          state := s
          context := c
          Output.emitIterationDone format iteration false failed.length state.isTerminal
      | _ => break  -- unreachable: while guard ensures non-terminal
  catch error =>
    Output.emitLoopError format s!"interrupted: {error}" (repr state).pretty
    return (1 : UInt32)
  -- Output final result
  Output.emitLoopResult format spec.name state loopConfig.stuckThreshold allExecutions
  return match state with
    | .passed _ => 0
    | _ => 1

end Qed.WorkerLoop
