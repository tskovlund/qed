set_option autoImplicit false

namespace Qed.Shell

/-- Result of a command execution with timeout enforcement.
    Distinguishes genuine process completion from timeout kills,
    avoiding sentinel exit codes (e.g. 124) that could collide
    with real process exit codes. -/
inductive TimeoutResult where
  | completed (exitCode : UInt32) (stdout : String) (stderr : String) (elapsedMs : Nat)
  | timedOut (stdout : String) (stderr : String) (elapsedMs : Nat)

/-- The shell command and argument used to execute commands on this platform.
    Unix (macOS, Linux, NixOS) uses `/bin/sh -c`, Windows uses `cmd /c`. -/
def shellCmd : String × String :=
  if System.Platform.isWindows then ("cmd", "/c") else ("/bin/sh", "-c")

/-- Quote a string for shell use (single-quote wrapping with escape). -/
def shellQuote (s : String) : String :=
  "'" ++ s.replace "'" "'\\''" ++ "'"

/-- Build a shell command string with exported environment variables.
    Each entry in `envVars` is `(name, value)` — values are shell-quoted.
    The `command` is appended after all exports.
    Precondition: `name` must be a valid shell identifier (alphanumeric + underscore).
    All callers use constants from `Agent.lean`. -/
def buildShellCommand (envVars : List (String × String)) (command : String) : String :=
  let exports := envVars.map fun (name, value) =>
    s!"export {name}={shellQuote value}"
  let exportString := String.intercalate "; " exports
  if exports.isEmpty then command
  else s!"{exportString}; {command}"

/-- Run a shell command and return (exitCode, stdout, stderr).
    Catches non-UTF-8 output (Lean's IO.Process.output throws when the process
    emits bytes that aren't valid UTF-8). -/
def runShellCommand (command : String) (workdir : Option String := none)
    : IO (UInt32 × String × String) := do
  let (cmd, flag) := shellCmd
  try
    let result ← IO.Process.output {
      cmd := cmd
      args := #[flag, command]
      cwd := workdir
    }
    return (result.exitCode, result.stdout, result.stderr)
  catch error =>
    return ((1 : UInt32), "", s!"process error: {error}")

/-- Polling interval for process timeout checks (milliseconds). -/
private def pollIntervalMs : UInt32 := 100

/-- Run a shell command with a timeout (in seconds). Returns a `TimeoutResult`
    that distinguishes genuine completion from timeout kills.
    The timeout is approximate (lower bound) — polling overhead may add a few
    milliseconds beyond the configured budget.
    Uses `setsid := true` on Unix to kill the entire process group. -/
def runShellCommandWithTimeout (command : String) (timeoutSeconds : Nat)
    (workdir : Option String := none) : IO TimeoutResult := do
  let (cmd, flag) := shellCmd
  try
    let child ← IO.Process.spawn {
      cmd := cmd
      args := #[flag, command]
      cwd := workdir
      stdout := .piped
      stderr := .piped
      stdin := .null
      setsid := !System.Platform.isWindows
    }
    let stdoutTask ← IO.asTask child.stdout.readToEnd Task.Priority.dedicated
    let stderrTask ← IO.asTask child.stderr.readToEnd Task.Priority.dedicated
    let budgetMs := timeoutSeconds * 1000
    let mut elapsed : Nat := 0
    let mut result : Option UInt32 := none
    while elapsed < budgetMs do
      match ← child.tryWait with
      | some exitCode =>
        result := some exitCode
        break
      | none =>
        IO.sleep pollIntervalMs
        elapsed := elapsed + pollIntervalMs.toNat
    match result with
    | some exitCode =>
      let stdout ← IO.ofExcept stdoutTask.get
      let stderr ← IO.ofExcept stderrTask.get
      return .completed exitCode stdout stderr elapsed
    | none =>
      -- Timeout: kill the process and collect partial output
      child.kill
      let _ ← child.wait
      let stdout ← IO.ofExcept stdoutTask.get
      let stderr ← IO.ofExcept stderrTask.get
      return .timedOut stdout stderr elapsed
  catch error =>
    return .completed (1 : UInt32) "" s!"process error: {error}" 0

end Qed.Shell
