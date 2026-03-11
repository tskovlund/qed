import Qed.Types
import Qed.Shell
import Qed.Agent
import Qed.Output
import Lean.Data.Json

namespace Qed.Verifier

open Qed

/-- Maximum characters of command output to preserve (keeps the tail, most
    recent output is most useful for debugging). -/
def maxOutputLength : Nat := 2000

/-- Truncate a string to the last `maxLength` characters, prepending a truncation marker. -/
private def truncate (s : String) (maxLength : Nat) : String :=
  if s.length > maxLength then
    "...(truncated)\n" ++ (s.drop (s.length - maxLength))
  else s

/-- Run a shell command and return pass/fail based on exit code.
    Captures stdout and stderr, truncates to last `maxOutputLength` chars.
    Enforces the configured timeout — kills the process if it exceeds it. -/
private def formatOutput (stdout stderr : String) : String :=
  let stdoutStr := stdout.trimAscii.toString
  let stderrStr := stderr.trimAscii.toString
  let combined := stdoutStr ++ (if stderrStr.isEmpty then "" else "\nSTDERR:\n" ++ stderrStr)
  truncate combined maxOutputLength

private def verifyCommand (command : String) (timeout : Nat) : IO VerificationResult := do
  let result ← Shell.runShellCommandWithTimeout command timeout
  match result with
  | .timedOut stdout stderr =>
    return .fail s!"timed out after {timeout}s\n{formatOutput stdout stderr}"
  | .completed exitCode stdout stderr =>
    let details := formatOutput stdout stderr
    if exitCode == 0 then
      return .pass details
    else
      return .fail s!"exit code {exitCode}\n{details}"

/-- The system prompt instructs the agent to produce a structured JSON verdict. -/
private def agentSystemPrompt : String :=
  "You are a code reviewer verifying an acceptance criterion. " ++
  "Review the codebase according to the instructions below. " ++
  "You MUST end your response with a JSON block on its own line:\n" ++
  "```json\n{\"pass\": true}\n```\n" ++
  "or\n" ++
  "```json\n{\"pass\": false, \"reason\": \"explanation\"}\n```\n" ++
  "Before the JSON block, write your analysis. The JSON block must be the last thing in your response."

/-- Extract the JSON verdict from the agent's response.
    Finds the last ```json block, or falls back to searching for raw JSON
    with a "pass" field. -/
def parseAgentVerdict (response : String) : Except String Bool := do
  -- Strategy: split by ```json, take the last block before ```, parse it
  let parts := response.splitOn "```json"
  if parts.length < 2 then
    -- No ```json block — heuristic fallback: search for a line that looks
    -- like JSON with a "pass" field. May match analysis text, but Json.parse
    -- rejects non-JSON lines, limiting false positives.
    let lines := response.splitOn "\n"
    let verdictLine := lines.reverse.find? fun line =>
      line.contains "\"pass\"" && (line.contains "true" || line.contains "false")
    match verdictLine with
    | none => .error "no verdict found in agent response (expected ```json block with {\"pass\": true/false})"
    | some line =>
      let trimmed := line.trimAscii.toString
      match Lean.Json.parse trimmed with
      | .error e => .error s!"found verdict-like line but failed to parse: {e}"
      | .ok json =>
        match json.getObjValAs? Bool "pass" with
        | .ok passed => .ok passed
        | .error _ => .error "verdict JSON missing boolean \"pass\" field"
  else
    -- Take everything after the last ```json marker (safe: parts.length ≥ 2)
    let lastPart := parts.getLastD ""
    -- Find the closing ``` (safe: splitOn always returns ≥ 1 element)
    let beforeClose := (lastPart.splitOn "```").headD ""
    let jsonStr := beforeClose.trimAscii.toString
    match Lean.Json.parse jsonStr with
    | .error e => .error s!"invalid JSON in verdict block: {e}"
    | .ok json =>
      match json.getObjValAs? Bool "pass" with
      | .ok passed => .ok passed
      | .error _ => .error "verdict JSON missing boolean \"pass\" field"

/-- Run an LLM agent to verify a criterion.
    The agent command receives the prompt via `$QED_VERIFIER_PROMPT` env var
    and the verdict format instructions via `$QED_VERIFIER_SYSTEM_PROMPT`.
    If no command is specified, defaults to Claude CLI. -/
private def verifyAgent (prompt : String) (model : String) (command : Option String)
    (timeout : Nat) : IO VerificationResult := do
  let agentCmd := command.getD (Agent.defaultVerifierCommand model)
  let envVars := [(Agent.verifierPromptVar, prompt), (Agent.verifierSystemPromptVar, agentSystemPrompt)]
  let shellCommand := Shell.buildShellCommand envVars agentCmd
  let result ← Shell.runShellCommandWithTimeout shellCommand timeout
  match result with
  | .timedOut stdout stderr =>
    return .fail s!"agent timed out after {timeout}s\n{formatOutput stdout stderr}"
  | .completed exitCode stdout stderr =>
    if exitCode != 0 then
      let stderrStr := stderr.trimAscii.toString
      if Agent.isUnavailable exitCode stderrStr then
        return .fail s!"agent unavailable: {truncate stderrStr maxOutputLength}"
      else
        return .fail s!"agent exited with code {exitCode}\n{truncate stderrStr maxOutputLength}"
    let response := stdout.trimAscii.toString
    match parseAgentVerdict response with
    | .ok true => return .pass (truncate response maxOutputLength)
    | .ok false => return .fail (truncate response maxOutputLength)
    | .error e => return .fail s!"could not parse agent verdict: {e}\n{truncate response maxOutputLength}"

/-- Prompt a human to verify a criterion interactively. Prints the instruction
    to stderr and reads a y/n response from stdin. Retries on invalid input.
    Fails if stdin is not available (non-interactive context). -/
private partial def promptLoop (stdin : IO.FS.Stream) : IO VerificationResult := do
  let line ← try
    let l ← stdin.getLine
    pure l.trimAscii.toString.toLower
  catch _ =>
    pure ""
  match line with
  | "y" | "yes" => return .pass "accepted by human"
  | "n" | "no" => return .fail "rejected by human"
  | "" => return .fail "non-interactive context"
  | _ =>
    IO.eprint s!"    Invalid input. {Output.ansiCyan}Accept? [y/n]:{Output.ansiReset} "
    promptLoop stdin

private def verifyHuman (_description : String) (instruction : String) : IO VerificationResult := do
  let indent := "    "
  let termWidth ← Output.getTerminalWidth
  let wrapWidth := if termWidth > indent.length + 20 then termWidth - indent.length else 60
  let lines := instruction.splitOn "\n"
  for line in lines do
    let trimmed := line.trimAscii.toString
    if !trimmed.isEmpty then
      let wrapped := Output.wordWrap trimmed wrapWidth
      for wrappedLine in wrapped do
        IO.eprintln s!"{indent}{Output.ansiDim}{wrappedLine}{Output.ansiReset}"
  IO.eprint s!"{indent}{Output.ansiCyan}Accept? [y/n]:{Output.ansiReset} "
  let stdin ← IO.getStdin
  promptLoop stdin

/-- Derive the Lean module name from a fully qualified theorem target.
    E.g., `Qed.Proofs.Termination.loop_terminates` → `Qed.Proofs.Termination`. -/
private def targetToModule (target : String) : Option String :=
  let parts := target.splitOn "."
  if parts.length < 2 then none
  else some (String.intercalate "." (parts.dropLast))

/-- Derive the source file path from a Lean module name.
    E.g., `Qed.Proofs.Termination` → `Qed/Proofs/Termination.lean`. -/
private def moduleToPath (module : String) : String :=
  module.replace "." "/" ++ ".lean"

/-- The placeholder axiom that marks incomplete proofs in Lean 4. -/
private def sorryKeyword : String := "sorry"

/-- Verify a formal proof by checking that the target's module compiles
    and contains no incomplete proof placeholders. Currently supports Lean 4 only. -/
private def verifyProof (prover : String) (target : String) : IO VerificationResult := do
  if prover != "lean4" then
    return .fail s!"unsupported prover: '{prover}' (supported: lean4)"
  match targetToModule target with
  | none => return .fail s!"invalid target: '{target}' (expected fully qualified name like Module.theorem)"
  | some module =>
    let sourcePath := moduleToPath module
    if !(← System.FilePath.pathExists sourcePath) then
      return .fail s!"source file not found: {sourcePath}"
    -- Reject files containing incomplete proof placeholders
    let contents ← IO.FS.readFile sourcePath
    let hasPlaceholder := (contents.splitOn sorryKeyword).length > 1
    if hasPlaceholder then
      return .fail s!"source file contains {sorryKeyword}: {sourcePath}"
    -- Build the module to verify the proof typechecks
    let buildResult ← Shell.runShellCommandWithTimeout s!"lake build {module}" defaultCommandTimeout
    match buildResult with
    | .timedOut stdout stderr =>
      return .fail s!"proof build timed out after {defaultCommandTimeout}s\n{formatOutput stdout stderr}"
    | .completed exitCode stdout stderr =>
      if exitCode == 0 then
        return .pass s!"theorem {target} verified (module {module} builds, complete)"
      else
        return .fail s!"proof build failed\n{formatOutput stdout stderr}"

/-- Verify a single acceptance criterion. Skipped criteria return immediately
    without dispatching to any verifier. -/
def verifyCriterion (criterion : AcceptanceCriterion) : IO VerificationResult := do
  match criterion.skip with
  | some reason => return .skipped reason
  | none =>
    match criterion.verify with
    | .command run timeout => verifyCommand run timeout
    | .agent prompt model command timeout => verifyAgent prompt model command timeout
    | .property run timeout => verifyCommand run timeout
    | .proof prover target => verifyProof prover target
    | .human instruction =>
      verifyHuman criterion.description instruction

/-- Verify all criteria in a spec, returning results paired with descriptions. -/
def verifyAll (criteria : List AcceptanceCriterion) : IO (List (String × VerificationResult)) := do
  criteria.mapM fun criterion => do
    let result ← verifyCriterion criterion
    return (criterion.description, result)

end Qed.Verifier
