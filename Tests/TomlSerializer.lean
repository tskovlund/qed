import Qed

set_option autoImplicit false

open Qed Qed.TomlSerializer Qed.TomlParser

/-- Helper: render a spec to TOML, parse it back, check the pairs match. -/
private def roundtripTest (spec : Spec) : IO Bool := do
  -- Act
  let toml := specToToml spec
  let result := parseDoc toml
  -- Assert
  match result with
  | .ok parsedPairs =>
    let expected := specToTomlPairs spec
    if toJson (.table parsedPairs) == toJson (.table expected) then
      return true
    else
      IO.eprintln s!"  roundtrip mismatch\n  rendered:\n{toml}"
      return false
  | .error errorInfo =>
    IO.eprintln s!"  parse error: {errorInfo}\n  rendered:\n{toml}"
    return false

def testRenderValueString : IO Bool := do
  -- Arrange / Act / Assert
  return renderValue (.str "hello") == "\"hello\""

def testRenderValueStringWithQuotes : IO Bool := do
  -- Arrange / Act / Assert
  return renderValue (.str "say \"hi\"") == "\"say \\\"hi\\\"\""

def testRenderValueStringWithBackslash : IO Bool := do
  -- Arrange / Act / Assert
  return renderValue (.str "path\\to") == "\"path\\\\to\""

def testRenderValueMultiLineString : IO Bool := do
  -- Arrange / Act / Assert
  let result := renderValue (.str "line1\nline2")
  let hasLine1 := decide ((result.splitOn "line1").length > 1)
  let hasLine2 := decide ((result.splitOn "line2").length > 1)
  return hasLine1 && hasLine2

def testRenderValueInt : IO Bool := do
  -- Arrange / Act / Assert
  return renderValue (.int 42) == "42"

def testRenderValueBool : IO Bool := do
  -- Arrange / Act / Assert
  return renderValue (.bool true) == "true" && renderValue (.bool false) == "false"

def testRenderValueArray : IO Bool := do
  -- Arrange / Act / Assert
  return renderValue (.array [.str "a", .str "b"]) == "[\"a\", \"b\"]"

def testRoundtripVerifySpec : IO Bool := do
  -- Arrange
  let spec : Spec := {
    name := "test-spec"
    mode := .verify
    criteria := [{
      description := "builds"
      verify := .command "make" 300 none
      schedule := .always
      skip := none
    }]
  }
  -- Act / Assert
  roundtripTest spec

def testRoundtripWorkerLoopSpec : IO Bool := do
  -- Arrange
  let spec : Spec := {
    name := "worker-test"
    mode := .workerLoop
      { command := some "claude", prompt := some "do the thing", model := "claude-opus-4-6", workdir := ".", timeout := 3600 }
      { maxIterations := 10, stuckThreshold := 3 }
    criteria := [{
      description := "tests pass"
      verify := .command "make test" 300 none
      schedule := .always
      skip := none
    }]
  }
  -- Act / Assert
  roundtripTest spec

def testRoundtripMultipleCriteria : IO Bool := do
  -- Arrange
  let spec : Spec := {
    name := "multi-criteria"
    mode := .verify
    criteria := [
      { description := "command criterion", verify := .command "echo ok" 60 none, schedule := .always, skip := none },
      { description := "proof criterion", verify := .proof "lean4" "My.Theorem", schedule := .always, skip := none },
      { description := "skipped one", verify := .human "check it", schedule := .manual, skip := some "not yet" }
    ]
  }
  -- Act / Assert
  roundtripTest spec

def testRoundtripAgentWithCommand : IO Bool := do
  -- Arrange
  let spec : Spec := {
    name := "agent-test"
    mode := .verify
    criteria := [{
      description := "agent review"
      verify := .agent "Review the code" "claude-opus-4-6" (some "my-agent") 600
      schedule := .heavy
      skip := none
    }]
  }
  -- Act / Assert
  roundtripTest spec

def testRoundtripCommandWithLock : IO Bool := do
  -- Arrange
  let spec : Spec := {
    name := "lock-test"
    mode := .verify
    criteria := [{
      description := "locked command"
      verify := .command "make" 300 (some ["src/**/*.lean", "lakefile.lean"])
      schedule := .always
      skip := none
    }]
  }
  -- Act / Assert
  roundtripTest spec

def testRoundtripMultiLinePrompt : IO Bool := do
  -- Arrange
  let spec : Spec := {
    name := "multiline-test"
    mode := .workerLoop
      { command := none, prompt := some "Line one.\nLine two.\nLine three.", model := "claude-opus-4-6", workdir := ".", timeout := 3600 }
      { maxIterations := 5, stuckThreshold := 2 }
    criteria := [{
      description := "it works"
      verify := .command "true" 60 none
      schedule := .always
      skip := none
    }]
  }
  -- Act / Assert
  roundtripTest spec

def tomlSerializerTests : List (String × IO Bool) := [
  ("testRenderValueString", testRenderValueString),
  ("testRenderValueStringWithQuotes", testRenderValueStringWithQuotes),
  ("testRenderValueStringWithBackslash", testRenderValueStringWithBackslash),
  ("testRenderValueMultiLineString", testRenderValueMultiLineString),
  ("testRenderValueInt", testRenderValueInt),
  ("testRenderValueBool", testRenderValueBool),
  ("testRenderValueArray", testRenderValueArray),
  ("testRoundtripVerifySpec", testRoundtripVerifySpec),
  ("testRoundtripWorkerLoopSpec", testRoundtripWorkerLoopSpec),
  ("testRoundtripMultipleCriteria", testRoundtripMultipleCriteria),
  ("testRoundtripAgentWithCommand", testRoundtripAgentWithCommand),
  ("testRoundtripCommandWithLock", testRoundtripCommandWithLock),
  ("testRoundtripMultiLinePrompt", testRoundtripMultiLinePrompt)
]
