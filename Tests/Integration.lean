import Qed

open Qed

def testTomlToJsonConvertsValidToml : IO Bool := do
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

def testTomlToJsonErrorsOnInvalidToml : IO Bool := do
  -- Arrange
  let toml := "[[[invalid toml"
  -- Act
  let result ← TomlConverter.tomlToJson toml
  -- Assert
  match result with
  | .ok _ => return false
  | .error _ => return true

def testLoadSpecParsesJsonFile : IO Bool := do
  -- Arrange / Act
  let result ← SpecLoader.loadSpec "specs/build.spec.json"
  -- Assert
  match result with
  | .ok spec =>
    return spec.name.contains "build" && spec.mode == SpecMode.verify
  | .error e =>
    IO.eprintln s!"  load error: {e}"
    return false

def testLoadSpecParsesTomlFile : IO Bool := do
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

def testListAllSpecsReturnsBothFormats : IO Bool := do
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

def testTomlMultiLineStringPreservesContent : IO Bool := do
  -- Arrange — multi-line strings are the main reason TOML exists for specs
  let toml := "name = \"review\"\n\n[[criteria]]\ndescription = \"code review\"\n\n[criteria.verify]\ntype = \"agentReview\"\nprompt = \"\"\"\nReview the code.\nCheck for:\n1. Correctness\n2. Style\n\"\"\"\n"
  -- Act
  match ← TomlConverter.tomlToJson toml with
  | .error e =>
    IO.eprintln s!"  toml error: {e}"
    return false
  | .ok json =>
    match Parser.parseJson json with
    | .error e =>
      IO.eprintln s!"  parse error: {e}"
      return false
    | .ok spec =>
      -- Assert
      match spec.criteria.head? with
      | some criterion =>
        return match criterion.verify with
          | .agentReview prompt _ => prompt.contains "Correctness" && prompt.contains "Style"
          | _ => false
      | none => return false

def integrationTests : List (String × IO Bool) := [
  ("testTomlToJsonConvertsValidToml", testTomlToJsonConvertsValidToml),
  ("testTomlToJsonErrorsOnInvalidToml", testTomlToJsonErrorsOnInvalidToml),
  ("testLoadSpecParsesJsonFile", testLoadSpecParsesJsonFile),
  ("testLoadSpecParsesTomlFile", testLoadSpecParsesTomlFile),
  ("testListAllSpecsReturnsBothFormats", testListAllSpecsReturnsBothFormats),
  ("testTomlMultiLineStringPreservesContent", testTomlMultiLineStringPreservesContent)
]
