import Qed

open Qed

def testTomlToJsonBasic : IO Bool := do
  -- Arrange
  let toml := "name = \"hello\"\n\n[[criteria]]\ndescription = \"builds\"\n\n[criteria.verify]\ntype = \"command\"\nrun = \"make\"\n"
  -- Act
  let result ← TomlConverter.tomlToJson toml
  -- Assert
  match result with
  | .ok json =>
    return json.contains "hello" && json.contains "command"
  | .error e =>
    IO.eprintln s!"  toml error: {e}"
    return false

def testTomlToJsonInvalidToml : IO Bool := do
  -- Arrange
  let toml := "[[[invalid toml"
  -- Act
  let result ← TomlConverter.tomlToJson toml
  -- Assert
  match result with
  | .ok _ => return false
  | .error _ => return true

def testLoadSpecFromJsonFile : IO Bool := do
  -- Arrange / Act
  let result ← SpecLoader.loadSpec "specs/build.spec.json"
  -- Assert
  match result with
  | .ok spec =>
    return spec.name.contains "build" && spec.mode == SpecMode.verify
  | .error e =>
    IO.eprintln s!"  load error: {e}"
    return false

def testLoadSpecFromTomlFile : IO Bool := do
  -- Arrange / Act
  let result ← SpecLoader.loadSpec "specs/state-machine.spec.toml"
  -- Assert
  match result with
  | .ok spec =>
    return spec.name == "state-machine-correctness" &&
      spec.mode == SpecMode.verify &&
      spec.criteria.length == 7
  | .error e =>
    IO.eprintln s!"  load error: {e}"
    return false

def testListAllSpecs : IO Bool := do
  -- Arrange / Act
  let result ← SpecLoader.listAllSpecs "specs"
  -- Assert
  match result with
  | .ok paths =>
    let hasJson := paths.any fun p => p.toString.endsWith ".spec.json"
    let hasToml := paths.any fun p => p.toString.endsWith ".spec.toml"
    return hasJson && hasToml && paths.length >= 3
  | .error e =>
    IO.eprintln s!"  list error: {e}"
    return false

def integrationTests : List (String × IO Bool) := [
  ("testTomlToJsonBasic", testTomlToJsonBasic),
  ("testTomlToJsonInvalidToml", testTomlToJsonInvalidToml),
  ("testLoadSpecFromJsonFile", testLoadSpecFromJsonFile),
  ("testLoadSpecFromTomlFile", testLoadSpecFromTomlFile),
  ("testListAllSpecs", testListAllSpecs)
]
