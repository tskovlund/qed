import Qed.Types
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

/-- The shell command and argument used to execute commands on this platform.
    Unix (macOS, Linux, NixOS) uses `/bin/sh -c`, Windows uses `cmd /c`. -/
private def shellCmd : String × String :=
  if System.Platform.isWindows then ("cmd", "/c") else ("/bin/sh", "-c")

/-- Run a shell command and return pass/fail based on exit code.
    Captures stdout and stderr, truncates to last `maxOutputLength` chars.
    Catches non-UTF-8 output (Lean's IO.Process.output throws when the process
    emits bytes that aren't valid UTF-8).
    TODO: `timeout` is parsed and stored but not yet enforced. Process-level
    timeout requires `IO.Process.spawn` + async kill, tracked for a future PR. -/
private def verifyCommand (command : String) (_timeout : Nat) : IO VerificationResult := do
  let (cmd, flag) := shellCmd
  let result ← try
    IO.Process.output {
      cmd := cmd
      args := #[flag, command]
    }
  catch error =>
    return .fail s!"command execution error: {error}"
  let stdout := result.stdout.trimAscii.toString
  let stderr := result.stderr.trimAscii.toString
  let combined := stdout ++ (if stderr.isEmpty then "" else "\nSTDERR:\n" ++ stderr)
  let details := truncate combined maxOutputLength
  if result.exitCode == 0 then
    return .pass details
  else
    return .fail s!"exit code {result.exitCode}\n{details}"

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
    Finds the last line containing `"pass"` within a ```json block,
    or falls back to searching for `{"pass":` anywhere in the response. -/
def parseAgentVerdict (response : String) : Except String Bool := do
  -- Strategy: split by ```json, take the last block before ```, parse it
  let parts := response.splitOn "```json"
  if parts.length < 2 then
    -- No ```json block — try to find raw JSON with "pass" field
    let lines := response.splitOn "\n"
    let verdictLine := lines.reverse.find? fun line =>
      line.contains "\"pass\"" && (line.contains "true" || line.contains "false")
    match verdictLine with
    | none => .error "no verdict found in agent response (expected ```json block with {\"pass\": true/false})"
    | some line =>
      let trimmed := line.trim
      match Lean.Json.parse trimmed with
      | .error e => .error s!"found verdict-like line but failed to parse: {e}"
      | .ok json =>
        match json.getObjValAs? Bool "pass" with
        | .ok passed => .ok passed
        | .error _ => .error "verdict JSON missing boolean \"pass\" field"
  else
    -- Take everything after the last ```json marker
    let lastPart := parts.getLast!
    -- Find the closing ```
    let beforeClose := (lastPart.splitOn "```").head!
    let jsonStr := beforeClose.trim
    match Lean.Json.parse jsonStr with
    | .error e => .error s!"invalid JSON in verdict block: {e}"
    | .ok json =>
      match json.getObjValAs? Bool "pass" with
      | .ok passed => .ok passed
      | .error _ => .error "verdict JSON missing boolean \"pass\" field"

/-- Quote a string for shell use (single-quote wrapping with escape). -/
private def shellQuote (s : String) : String :=
  "'" ++ s.replace "'" "'\\''" ++ "'"

/-- Build the default agent shell command for Claude CLI. -/
private def defaultAgentCommand (model : String) : String :=
  s!"claude -p \"$QED_AGENT_PROMPT\" --model {model} --system-prompt \"$QED_AGENT_SYSTEM_PROMPT\" --output-format text --max-turns 1"

/-- Run an LLM agent to verify a criterion.
    The agent command receives the prompt via `$QED_AGENT_PROMPT` env var
    and the verdict format instructions via `$QED_AGENT_SYSTEM_PROMPT`.
    If no command is specified, defaults to Claude CLI. -/
private def verifyAgent (prompt : String) (model : String) (command : Option String) : IO VerificationResult := do
  let agentCmd := command.getD (defaultAgentCommand model)
  let (cmd, flag) := shellCmd
  let shellCommand := s!"export QED_AGENT_PROMPT={shellQuote prompt}; export QED_AGENT_SYSTEM_PROMPT={shellQuote agentSystemPrompt}; {agentCmd}"
  let result ← try
    IO.Process.output {
      cmd := cmd
      args := #[flag, shellCommand]
    }
  catch error =>
    return .skipped s!"agent unavailable: {error}"
  if result.exitCode != 0 then
    let stderr := result.stderr.trimAscii.toString
    -- Distinguish environment/setup errors (skip) from genuine review failures (fail)
    if stderr.contains "not found" || stderr.contains "No such file" ||
       stderr.contains "cannot be launched" || result.exitCode == 127 then
      return .skipped s!"agent unavailable: {truncate stderr maxOutputLength}"
    else
      return .fail s!"agent exited with code {result.exitCode}\n{truncate stderr maxOutputLength}"
  let response := result.stdout.trimAscii.toString
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
