import Qed.Types

namespace Qed.SpecLoader

open Qed

/-- Load a spec file from disk and parse it into a Spec. -/
def loadSpec (path : System.FilePath) : IO (Except String Spec) := do
  let contents ← IO.FS.readFile path
  -- TODO: parse JSON/TOML into Spec once Parser is implemented (TSK-154)
  return .error s!"Parsing not yet implemented for: {contents.take 50}..."

/-- List all spec files in a directory matching the given extension. -/
def listSpecs (directory : System.FilePath) (extension : String := ".spec.json")
    : IO (Except String (List System.FilePath)) := do
  let entries ← directory.readDir
  let specFiles := entries.filter fun entry =>
    entry.fileName.endsWith extension
  let paths := specFiles.map fun entry =>
    directory / entry.fileName
  return .ok paths.toList

end Qed.SpecLoader
