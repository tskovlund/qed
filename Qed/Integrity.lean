import Qed.Types

namespace Qed.Integrity

open Qed

/-- Try running a hash command on a file, returning the hex digest or none. -/
private def tryHashCmd (cmd : String) (args : Array String) : IO (Option String) := do
  try
    let result ← IO.Process.output { cmd := cmd, args := args }
    if result.exitCode == 0 then
      -- Output format: "<hash>  <filename>" or "<hash> <filename>"
      return some (result.stdout.trimAscii.takeWhile (· != ' ')).toString
    else
      return none
  catch _ =>
    return none

/-- Compute SHA-256 hash of a file's raw bytes.
    Tries `shasum -a 256` (macOS/BSD), falls back to `sha256sum` (GNU coreutils). -/
def hashFile (path : System.FilePath) : IO String := do
  let pathStr := path.toString
  match ← tryHashCmd "shasum" #["-a", "256", pathStr] with
  | some hash => return hash
  | none =>
    match ← tryHashCmd "sha256sum" #[pathStr] with
    | some hash => return hash
    | none => throw (IO.userError s!"cannot compute SHA-256 hash: neither shasum nor sha256sum available")

/-- Compute SHA-256 hash of in-memory contents.
    Writes to a temp file to avoid TOCTOU races (hash the bytes we actually parsed). -/
def hashContents (contents : String) : IO String := do
  let timestamp ← IO.monoMsNow
  let pid ← IO.Process.getPID
  let tmpDir := (← IO.getEnv "TMPDIR").getD "/tmp"
  let tmpPath : System.FilePath := s!"{tmpDir}/qed-hash-{pid}-{timestamp}"
  IO.FS.writeFile tmpPath contents
  try
    let hash ← hashFile tmpPath
    IO.FS.removeFile tmpPath
    return hash
  catch error =>
    try IO.FS.removeFile tmpPath catch _ => pure ()
    throw error

/-- Check if a file's current hash matches the expected hash. -/
def checkIntegrity (path : System.FilePath) (expectedHash : String) : IO (Except String Unit) := do
  try
    let currentHash ← hashFile path
    if currentHash == expectedHash then
      return .ok ()
    else
      return .error s!"spec file '{path}' was modified during execution (hash mismatch)"
  catch error =>
    return .error s!"integrity check failed for '{path}': {error}"

/-- Check git cleanliness of a file (for --pin mode).
    Returns .ok if the file matches its committed version,
    .error with a description if it has uncommitted changes. -/
def checkGitClean (path : System.FilePath) : IO (Except String Unit) := do
  let pathStr := path.toString
  try
    let result ← IO.Process.output {
      cmd := "git"
      args := #["diff", "HEAD", "--exit-code", pathStr]
    }
    if result.exitCode == 0 then
      -- Also check if the file is tracked
      let tracked ← IO.Process.output {
        cmd := "git"
        args := #["ls-files", "--error-unmatch", pathStr]
      }
      if tracked.exitCode == 0 then
        return .ok ()
      else
        return .error s!"spec file '{path}' is not tracked by git"
    else
      return .error s!"spec file '{path}' has uncommitted changes"
  catch error =>
    return .error s!"git check failed for '{path}': {error}"

/-- Run all integrity checks for a pinned spec.
    Hash check always runs. Git check only runs if `pinned` is true. -/
def verify (pinnedSpec : Spec.Pinned) (pinned : Bool) : IO (Except String Unit) := do
  match ← checkIntegrity pinnedSpec.path pinnedSpec.contentHash with
  | .error reason => return .error reason
  | .ok () =>
    if pinned then
      checkGitClean pinnedSpec.path
    else
      return .ok ()

end Qed.Integrity
