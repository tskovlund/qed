import Qed.Types
import Qed.Parser
import Qed.TomlConverter
import Qed.Integrity

namespace Qed.SpecLoader

open Qed

/-- Path to the ignore file (relative to project root). -/
def ignoreFilePath : String := ".qedignore"

/-- Default ignore patterns when no .qedignore file exists. -/
def defaultIgnorePatterns : List String := ["archive", "wip"]

/-- Read ignore patterns from a .qedignore file. Falls back to default patterns
    (archive, wip) when the file doesn't exist. When the file exists, its contents
    are authoritative — no defaults are merged.
    Format: one name per line, `#` for comments, blank lines skipped. -/
def readIgnorePatterns (directory : System.FilePath) : IO (List String) := do
  let path := directory / ignoreFilePath
  if ← path.pathExists then
    let contents ← IO.FS.readFile path
    return contents.splitOn "\n"
      |>.map (·.trimAsciiEnd.toString)
      |>.filter fun line => !line.isEmpty && !line.startsWith "#"
  else
    return defaultIgnorePatterns

/-- Match a pattern against a name. Supports `*` as a wildcard.
    Patterns: `archive` (exact), `*.bak` (suffix), `temp*` (prefix),
    `*test*` (contains), `pre*suf` (prefix + suffix). -/
def matchPattern (pattern : String) (name : String) : Bool :=
  if !pattern.contains '*' then
    pattern == name
  else
    let parts := pattern.splitOn "*"
    match parts with
    | ["", ""] =>
      true
    | ["", suf] =>
      name.endsWith suf
    | [pre, ""] =>
      name.startsWith pre
    | ["", inner, ""] =>
      inner.isEmpty || (name.splitOn inner).length > 1
    | [pre, suf] =>
      name.startsWith pre && name.endsWith suf &&
        name.length >= pre.length + suf.length
    | _ =>
      false

/-- Whether a file or directory name should be ignored. Matches against patterns
    from .qedignore (supports `*` wildcards). Hidden entries (starting with `.`)
    are always ignored. -/
def shouldIgnore (ignorePatterns : List String) (name : String) : Bool :=
  name.startsWith "." || ignorePatterns.any (matchPattern · name)

/-- Load a spec file from disk, parse it, and pin it to the file's current state.
    Returns a `Spec.Pinned` with the SHA-256 hash of the raw file bytes. -/
def loadSpec (path : System.FilePath) : IO (Except String Spec.Pinned) := do
  let contents ← IO.FS.readFile path
  let contentHash ← Integrity.hashContents contents
  let pathStr := path.toString
  let specResult := if pathStr.endsWith ".toml" then
    match TomlConverter.tomlToJson contents with
    | .error e => .error e
    | .ok json => Parser.parseJson json
  else
    Parser.parseJson contents
  match specResult with
  | .error e => return .error e
  | .ok spec => return .ok { spec, path, contentHash }

/-- List all spec files in a directory matching the given extension. -/
def listSpecs (directory : System.FilePath) (extension : String := ".spec.json")
    : IO (Except String (List System.FilePath)) := do
  let entries ← directory.readDir
  let specFiles := entries.filter fun entry =>
    entry.fileName.endsWith extension
  let paths := specFiles.map fun entry =>
    directory / entry.fileName
  return .ok paths.toList

/-- Recursively find all spec files (.spec.json and .spec.toml) under a directory. -/
def listAllSpecs (directory : System.FilePath)
    : IO (Except String (List System.FilePath)) := do
  -- Read the initial directory eagerly so errors (e.g., not found) propagate
  let _ ← directory.readDir
  let ignorePatterns ← readIgnorePatterns directory
  let mut specFiles : List System.FilePath := []
  let mut queue : List System.FilePath := [directory]
  while !queue.isEmpty do
    match queue with
    | [] => break
    | dir :: rest =>
      queue := rest
      let entries ← try
        dir.readDir
      catch _ =>
        -- Skip subdirectories we can't read
        continue
      for entry in entries do
        let path := dir / entry.fileName
        if entry.fileName.endsWith ".spec.json" || entry.fileName.endsWith ".spec.toml" then
          specFiles := specFiles ++ [path]
        else
          let isDir ← path.isDir
          if isDir && !shouldIgnore ignorePatterns entry.fileName then
            queue := queue ++ [path]
  return .ok specFiles

end Qed.SpecLoader
