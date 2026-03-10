import Qed.Types
import Qed.Shell
import Qed.Agent
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
    Catches non-UTF-8 output (Lean's IO.Process.output throws when the process
    emits bytes that aren't valid UTF-8).
    TODO: `timeout` is parsed and stored but not yet enforced. Process-level
    timeout requires `IO.Process.spawn` + async kill, tracked for a future PR. -/
private def verifyCommand (command : String) (_timeout : Nat) : IO VerificationResult := do
  let (exitCode, stdout, stderr) ← Shell.runShellCommand command
  let stdoutStr := stdout.trimAscii.toString
  let stderrStr := stderr.trimAscii.toString
  let combined := stdoutStr ++ (if stderrStr.isEmpty then "" else "\nSTDERR:\n" ++ stderrStr)
  let details := truncate combined maxOutputLength
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
private def verifyAgent (prompt : String) (model : String) (command : Option String) : IO VerificationResult := do
  let agentCmd := command.getD (Agent.defaultVerifierCommand model)
  let envVars := [(Agent.verifierPromptVar, prompt), (Agent.verifierSystemPromptVar, agentSystemPrompt)]
  let shellCommand := Shell.buildShellCommand envVars agentCmd
  let (exitCode, stdout, stderr) ← Shell.runShellCommand shellCommand
  if exitCode != 0 then
    let stderrStr := stderr.trimAscii.toString
    if Agent.isUnavailable exitCode stderrStr then
      return .skipped s!"agent unavailable: {truncate stderrStr maxOutputLength}"
    else
      return .fail s!"agent exited with code {exitCode}\n{truncate stderrStr maxOutputLength}"
  let response := stdout.trimAscii.toString
  match parseAgentVerdict response with
  | .ok true => return .pass (truncate response maxOutputLength)
  | .ok false => return .fail (truncate response maxOutputLength)
  | .error e => return .fail s!"could not parse agent verdict: {e}\n{truncate response maxOutputLength}"

/-- Verify a single acceptance criterion. -/
def verifyCriterion (criterion : AcceptanceCriterion) : IO VerificationResult := do
  match criterion.verify with
  | .command run timeout => verifyCommand run timeout
  | .agent prompt model command => verifyAgent prompt model command
  | .property run timeout =>
    return .skipped s!"property testing not yet implemented (run: {run}, timeout: {timeout})"
  | .proof prover target =>
    return .skipped s!"proof verification not yet implemented (prover: {prover}, target: {target})"
  | .human instruction =>
    return .needsHuman instruction

/-- Verify all criteria in a spec, returning results paired with descriptions. -/
def verifyAll (criteria : List AcceptanceCriterion) : IO (List (String × VerificationResult)) := do
  criteria.mapM fun criterion => do
    let result ← verifyCriterion criterion
    return (criterion.description, result)

end Qed.Verifier
