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

def testCliVersionPrintsVersion : IO Bool := do
  -- Arrange / Act
  let (exitCode, stdout, _) ← runQed ["version"]
  -- Assert
  return exitCode == 0 && stdout.trimAscii.toString.startsWith "qed " &&
    stdout.contains "0.1.0"

def testCliHelpPrintsUsage : IO Bool := do
  -- Arrange / Act
  let (exitCode, stdout, _) ← runQed ["help"]
  -- Assert
  return exitCode == 0 && stdout.contains "Usage:" &&
    stdout.contains "verify" && stdout.contains "parse"

def testCliParseValidSpec : IO Bool := do
  -- Arrange / Act
  let (exitCode, stdout, _) ← runQed ["parse", "specs/build.spec.json"]
  -- Assert
  return exitCode == 0 && stdout.contains "build"

def testCliParseInvalidFile : IO Bool := do
  -- Arrange / Act
  let (exitCode, _, stderr) ← runQed ["parse", "nonexistent.json"]
  -- Assert
  return exitCode == 1 && stderr.length > 0

def testCliVerifyPassingSpec : IO Bool := do
  -- Arrange — use a minimal spec with a trivially passing command
  let specContent := "{\"name\": \"cli-test\", \"criteria\": [{\"description\": \"trivial pass\", \"verify\": {\"type\": \"command\", \"run\": \"true\"}}]}"
  let specPath ← writeTempSpec specContent
  -- Act
  let (exitCode, stdout, _) ← runQed ["verify", specPath.toString]
  -- Assert
  return exitCode == 0 && stdout.contains "Verifying:" && stdout.contains "cli-test"

def testCliUnknownCommandFails : IO Bool := do
  -- Arrange / Act
  let (exitCode, _, stderr) ← runQed ["foo"]
  -- Assert
  return exitCode == 1 && stderr.contains "unknown command"

def cliTests : List (String × IO Bool) := [
  ("testCliVersionPrintsVersion", testCliVersionPrintsVersion),
  ("testCliHelpPrintsUsage", testCliHelpPrintsUsage),
  ("testCliParseValidSpec", testCliParseValidSpec),
  ("testCliParseInvalidFile", testCliParseInvalidFile),
  ("testCliVerifyPassingSpec", testCliVerifyPassingSpec),
  ("testCliUnknownCommandFails", testCliUnknownCommandFails)
]
