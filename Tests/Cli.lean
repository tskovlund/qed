import Qed

/-- Path to the built qed binary. -/
private def qedBinary : String := ".lake/build/bin/qed"

/-- Run the qed binary with the given arguments, return (exitCode, stdout, stderr). -/
private def runQed (args : List String) : IO (UInt32 × String × String) := do
  let result ← IO.Process.output {
    cmd := qedBinary
    args := args.toArray
  }
  return (result.exitCode, result.stdout, result.stderr)

/-- Create a temporary spec file for testing, returning its path. -/
private def writeTempSpec (content : String) : IO System.FilePath := do
  let path : System.FilePath := "/tmp/qed-test-cli.spec.json"
  IO.FS.writeFile path content
  return path

def testVersionPrintsVersionString : IO Bool := do
  -- Arrange / Act
  let (exitCode, stdout, _) ← runQed ["version"]
  -- Assert
  return exitCode == 0 && stdout.trimAscii.startsWith "qed " &&
    stdout.contains "0.1.0"

def testHelpPrintsUsageInfo : IO Bool := do
  -- Arrange / Act
  let (exitCode, stdout, _) ← runQed ["help"]
  -- Assert
  return exitCode == 0 && stdout.contains "Usage:" &&
    stdout.contains "verify" && stdout.contains "parse"

def testParseReturnsSuccessForValidSpec : IO Bool := do
  -- Arrange / Act
  let (exitCode, stdout, _) ← runQed ["parse", "specs/build.spec.json"]
  -- Assert
  return exitCode == 0 && stdout.contains "build"

def testParseReturnsErrorForMissingFile : IO Bool := do
  -- Arrange / Act
  let (exitCode, _, stderr) ← runQed ["parse", "nonexistent.json"]
  -- Assert
  return exitCode == 1 && stderr.length > 0

def testVerifyReturnsPassForPassingSpec : IO Bool := do
  -- Arrange
  let specContent := "{\"name\": \"cli-test\", \"criteria\": [{\"description\": \"trivial pass\", \"verify\": {\"type\": \"command\", \"run\": \"true\"}}]}"
  let specPath ← writeTempSpec specContent
  -- Act
  let (exitCode, stdout, _) ← runQed ["verify", specPath.toString]
  -- Assert
  return exitCode == 0 && stdout.contains "Verifying:" && stdout.contains "cli-test"

def testVerifyReturnsFailForFailingSpec : IO Bool := do
  -- Arrange
  let specContent := "{\"name\": \"fail-test\", \"criteria\": [{\"description\": \"always fails\", \"verify\": {\"type\": \"command\", \"run\": \"false\"}}]}"
  let specPath ← writeTempSpec specContent
  -- Act
  let (exitCode, stdout, stderr) ← runQed ["verify", specPath.toString]
  -- Assert
  return exitCode == 1 && stdout.contains "FAIL" && stderr.contains "failed"

def testVerifyJsonOutputReturnsValidJson : IO Bool := do
  -- Arrange
  let specContent := "{\"name\": \"json-test\", \"criteria\": [{\"description\": \"trivial pass\", \"verify\": {\"type\": \"command\", \"run\": \"true\"}}]}"
  let specPath ← writeTempSpec specContent
  -- Act
  let (exitCode, stdout, _) ← runQed ["verify", "--json", specPath.toString]
  -- Assert — output must be valid JSON with expected structure
  match Lean.Json.parse stdout with
  | .error _ => return false
  | .ok json =>
    let specOk := match json.getObjValAs? String "spec" with
      | .ok "json-test" => true | _ => false
    let passedOk := match json.getObjValAs? Bool "passed" with
      | .ok true => true | _ => false
    let hasCriteria := (json.getObjVal? "criteria").isOk
    return exitCode == 0 && specOk && passedOk && hasCriteria

def testVerifyJsonErrorReturnsJsonOnMissingFile : IO Bool := do
  -- Arrange / Act
  let (exitCode, stdout, _) ← runQed ["verify", "--json", "nonexistent.json"]
  -- Assert — error output should be valid JSON with error field
  match Lean.Json.parse stdout with
  | .error _ => return false
  | .ok json =>
    let hasError := (json.getObjValAs? String "error").isOk
    return exitCode == 1 && hasError

def testRunDispatchesToVerifyMode : IO Bool := do
  -- Arrange
  let specContent := "{\"name\": \"run-verify-test\", \"criteria\": [{\"description\": \"trivial pass\", \"verify\": {\"type\": \"command\", \"run\": \"true\"}}]}"
  let specPath ← writeTempSpec specContent
  -- Act
  let (exitCode, stdout, _) ← runQed ["run", specPath.toString]
  -- Assert
  return exitCode == 0 && stdout.contains "run-verify-test"

def testRunWorkerLoopPassesOnFirstIteration : IO Bool := do
  -- Arrange: worker does nothing, criterion always passes
  let specContent := "{\"name\": \"loop-pass\", \"worker\": {\"command\": \"true\"}, \"criteria\": [{\"description\": \"always passes\", \"verify\": {\"type\": \"command\", \"run\": \"true\"}}]}"
  let specPath ← writeTempSpec specContent
  -- Act
  let (exitCode, stdout, _) ← runQed ["run", specPath.toString]
  -- Assert
  return exitCode == 0 && stdout.contains "loop-pass" && stdout.contains "passed"

def testRunWorkerLoopJsonOutput : IO Bool := do
  -- Arrange
  let specContent := "{\"name\": \"loop-json\", \"worker\": {\"command\": \"true\"}, \"criteria\": [{\"description\": \"passes\", \"verify\": {\"type\": \"command\", \"run\": \"true\"}}]}"
  let specPath ← writeTempSpec specContent
  -- Act
  let (exitCode, stdout, _) ← runQed ["run", "--json", specPath.toString]
  -- Assert
  match Lean.Json.parse stdout with
  | .error _ => return false
  | .ok json =>
    let specOk := match json.getObjValAs? String "spec" with
      | .ok "loop-json" => true | _ => false
    let passedOk := match json.getObjValAs? Bool "passed" with
      | .ok true => true | _ => false
    return exitCode == 0 && specOk && passedOk

def testRunWorkerLoopReachesMaxIterations : IO Bool := do
  -- Arrange: worker does nothing, criterion always fails, max 2 iterations
  let specContent := "{\"name\": \"loop-max\", \"worker\": {\"command\": \"true\"}, \"maxIterations\": 2, \"criteria\": [{\"description\": \"always fails\", \"verify\": {\"type\": \"command\", \"run\": \"false\"}}]}"
  let specPath ← writeTempSpec specContent
  -- Act
  let (exitCode, _, stderr) ← runQed ["run", specPath.toString]
  -- Assert
  return exitCode == 1 && stderr.contains "maximum iterations"

def testRunWorkerLoopWithPrompt : IO Bool := do
  -- Arrange: Tier 1 worker with prompt, criterion always passes
  let specContent := "{\"name\": \"loop-prompt\", \"worker\": {\"command\": \"echo\", \"prompt\": \"Do the thing\"}, \"criteria\": [{\"description\": \"passes\", \"verify\": {\"type\": \"command\", \"run\": \"true\"}}]}"
  let specPath ← writeTempSpec specContent
  -- Act
  let (exitCode, stdout, _) ← runQed ["run", specPath.toString]
  -- Assert
  return exitCode == 0 && stdout.contains "loop-prompt" && stdout.contains "passed"

def testNoArgsShowsHelp : IO Bool := do
  -- Arrange / Act
  let (exitCode, stdout, _) ← runQed []
  -- Assert
  return exitCode == 0 && stdout.contains "Usage:" && stdout.contains "verify"

def testUnknownCommandReturnsError : IO Bool := do
  -- Arrange / Act
  let (exitCode, _, stderr) ← runQed ["foo"]
  -- Assert
  return exitCode == 1 && stderr.contains "unknown command"

def cliTests : List (String × IO Bool) := [
  ("testVersionPrintsVersionString", testVersionPrintsVersionString),
  ("testHelpPrintsUsageInfo", testHelpPrintsUsageInfo),
  ("testParseReturnsSuccessForValidSpec", testParseReturnsSuccessForValidSpec),
  ("testParseReturnsErrorForMissingFile", testParseReturnsErrorForMissingFile),
  ("testVerifyReturnsPassForPassingSpec", testVerifyReturnsPassForPassingSpec),
  ("testVerifyReturnsFailForFailingSpec", testVerifyReturnsFailForFailingSpec),
  ("testVerifyJsonOutputReturnsValidJson", testVerifyJsonOutputReturnsValidJson),
  ("testVerifyJsonErrorReturnsJsonOnMissingFile", testVerifyJsonErrorReturnsJsonOnMissingFile),
  ("testRunDispatchesToVerifyMode", testRunDispatchesToVerifyMode),
  ("testRunWorkerLoopPassesOnFirstIteration", testRunWorkerLoopPassesOnFirstIteration),
  ("testRunWorkerLoopJsonOutput", testRunWorkerLoopJsonOutput),
  ("testRunWorkerLoopReachesMaxIterations", testRunWorkerLoopReachesMaxIterations),
  ("testRunWorkerLoopWithPrompt", testRunWorkerLoopWithPrompt),
  ("testNoArgsShowsHelp", testNoArgsShowsHelp),
  ("testUnknownCommandReturnsError", testUnknownCommandReturnsError)
]
