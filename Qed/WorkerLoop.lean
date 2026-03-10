import Lean.Data.Json
import Qed.Types
import Qed.StateMachine
import Qed.Verifier
import Qed.Output

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
      ("status", Lean.Json.str (Output.resultStatus result)),
      ("details", Lean.Json.str (Output.resultDetails result))]
  let json := Lean.Json.arr entries.toArray
  IO.FS.writeFile path (json.pretty 2)
  return path

/-- The shell command and argument used to execute commands on this platform. -/
private def shellCmd : String × String :=
  if System.Platform.isWindows then ("cmd", "/c") else ("/bin/sh", "-c")

/-- Quote a string for shell use (single-quote wrapping with escape). -/
def shellQuote (s : String) : String :=
  "'" ++ s.replace "'" "'\\''" ++ "'"

/-- Spawn a worker process with the appropriate env vars and prompt handling.
    Catches non-UTF-8 output (Lean's IO.Process.output throws when the process
    emits bytes that aren't valid UTF-8). -/
def spawnWorker (worker : WorkerConfig)
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
  try
    let result ← IO.Process.output {
      cmd := cmd
      args := #[flag, shellCommand]
      cwd := if worker.workdir == "." then none else some worker.workdir
    }
    return (result.exitCode, result.stdout, result.stderr)
  catch error =>
    -- Non-UTF-8 output or other IO errors — report as failure
    return ((1 : UInt32), "", s!"worker process error: {error}")

/-- Run the worker loop: spawn worker, verify, feed failures back, repeat.
    Handles interruption (SIGINT) gracefully — Lean's runtime converts the
    signal into an IO exception, which we catch to report partial progress. -/
def run (spec : Spec) (worker : WorkerConfig) (loopConfig : LoopConfig)
    (jsonOutput : Bool) : IO UInt32 := do
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
    IO.println s!"Worker loop: {spec.name}"
    IO.println s!"  max iterations: {loopConfig.maxIterations}, stuck threshold: {loopConfig.stuckThreshold}"
    IO.println ""
  try
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
            IO.println s!"  Worker stderr: {stderr.trimAscii.take stderrPreviewLength}"
        -- Worker done → transition to verifying
        let (s, c) := step loopConfig state context .workerDone
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
            IO.println s!"    [{Output.statusIndicator result}] {description}"
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
      IO.eprintln s!"\nInterrupted: {error}"
      IO.eprintln s!"  State at interruption: {repr state}"
    return (1 : UInt32)
  -- Output final result
  if jsonOutput then
    let stateStr := match state with
      | .passed iterations => s!"passed after {iterations} iterations"
      | .stuck iterations _ => s!"stuck after {iterations} iterations"
      | .maxIterationsReached iterations => s!"max iterations reached ({iterations})"
      | .escalated reason => s!"escalated: {reason}"
      | _ => "unknown"
    let resultJson := Output.workerResultsToJson spec.name stateStr allResults
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

end Qed.WorkerLoop
