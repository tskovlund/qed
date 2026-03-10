import Qed.Types
import Qed.Parser
import Qed.TomlConverter

namespace Qed.SpecLoader

open Qed

/-- Load a spec file from disk and parse it into a Spec.
Dispatches to JSON or TOML parser based on file extension. -/
def loadSpec (path : System.FilePath) : IO (Except String Spec) := do
  let contents ← IO.FS.readFile path
  let pathStr := path.toString
  if pathStr.endsWith ".toml" then
    match TomlConverter.tomlToJson contents with
    | .error e => return .error e
    | .ok json => return Parser.parseJson json
  else
    return Parser.parseJson contents

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
        -- Skip directories we can't read (e.g., .lake, .git)
        continue
      for entry in entries do
        let path := dir / entry.fileName
        if entry.fileName.endsWith ".spec.json" || entry.fileName.endsWith ".spec.toml" then
          specFiles := specFiles ++ [path]
        else
          let isDir ← path.isDir
          -- Skip hidden directories and build artifacts
          if isDir && !entry.fileName.startsWith "." && entry.fileName != ".lake" then
            queue := queue ++ [path]
  return .ok specFiles

end Qed.SpecLoader
