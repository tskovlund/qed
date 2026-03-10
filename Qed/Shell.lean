namespace Qed.Shell

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
  let exportStr := String.intercalate "; " exports
  if exports.isEmpty then command
  else s!"{exportStr}; {command}"

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

end Qed.Shell
