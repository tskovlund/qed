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
    match ← TomlConverter.tomlToJson contents with
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

/-- List all spec files in a directory (both .spec.json and .spec.toml). -/
def listAllSpecs (directory : System.FilePath)
    : IO (Except String (List System.FilePath)) := do
  let jsonSpecs ← listSpecs directory ".spec.json"
  let tomlSpecs ← listSpecs directory ".spec.toml"
  match jsonSpecs, tomlSpecs with
  | .ok jsonList, .ok tomlList => return .ok (jsonList ++ tomlList)
  | .error e, _ | _, .error e => return .error e

end Qed.SpecLoader
