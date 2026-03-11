import Qed.Types
import Qed.Parser
import Qed.TomlConverter
import Qed.Integrity

namespace Qed.SpecLoader

open Qed

/-- Load a spec file from disk, parse it, and pin it to the file's current state.
    Returns a `Spec.Pinned` with the SHA-256 hash of the raw file bytes. -/
def loadSpec (path : System.FilePath) : IO (Except String Spec.Pinned) := do
  let contents ← IO.FS.readFile path
  let contentHash ← Integrity.hashFile path
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
          -- Skip hidden directories (includes .lake, .git, etc.)
          if isDir && !entry.fileName.startsWith "." then
            queue := queue ++ [path]
  return .ok specFiles

end Qed.SpecLoader
