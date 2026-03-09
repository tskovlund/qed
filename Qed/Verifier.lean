import Qed.Types

namespace Qed.Verifier

open Qed

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
    Captures stdout and stderr, truncates to last 2000 chars.
    TODO: `timeout` is parsed and stored but not yet enforced. Process-level
    timeout requires `IO.Process.spawn` + async kill, tracked for a future PR. -/
private def verifyCommand (command : String) (_timeout : Nat) : IO VerificationResult := do
  let (cmd, flag) := shellCmd
  let result ← IO.Process.output {
    cmd := cmd
    args := #[flag, command]
  }
  let stdout := result.stdout.trimAscii.toString
  let stderr := result.stderr.trimAscii.toString
  let combined := stdout ++ (if stderr.isEmpty then "" else "\nSTDERR:\n" ++ stderr)
  let details := truncate combined 2000
  if result.exitCode == 0 then
    return .pass details
  else
    return .fail s!"exit code {result.exitCode}\n{details}"

/-- Verify a single acceptance criterion. -/
def verifyCriterion (criterion : AcceptanceCriterion) : IO VerificationResult := do
  match criterion.verify with
  | .command run timeout => verifyCommand run timeout
  | .agentReview prompt model =>
    return .skipped s!"agentReview not yet implemented (model: {model}, prompt length: {prompt.length})"
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
