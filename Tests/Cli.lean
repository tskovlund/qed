import Qed

set_option autoImplicit false

/-- Relative path to the built qed binary. -/
private def qedBinaryRelative : String := ".lake/build/bin/qed"

/-- Resolve the qed binary to an absolute path so it works with any cwd. -/
private def resolveQedBinary : IO String := do
  let currentDirectory ← IO.currentDir
  return (currentDirectory / qedBinaryRelative).toString

/-- Run the qed binary with the given arguments, return (exitCode, stdout, stderr).
    Optionally set the working directory to avoid writing files in the repo root. -/
private def runQed (args : List String) (workDir : Option String := none) : IO (UInt32 × String × String) := do
  let binary ← resolveQedBinary
  let result ← IO.Process.output {
    cmd := binary
    args := args.toArray
    cwd := workDir
  }
  return (result.exitCode, result.stdout, result.stderr)

/-- Create a clean temporary directory for this test process.
    Uses PID for per-process uniqueness and removes any stale
    directory from a previous process that reused the same PID. -/
private def freshTempDir (label : String) : IO System.FilePath := do
  let pid ← IO.Process.getPID
  let path : System.FilePath := s!"/tmp/qed-test-{label}-{pid}"
  let _ ← IO.Process.output { cmd := "rm", args := #["-rf", path.toString] }
  IO.FS.createDirAll path
  return path

/-- Create a temporary spec file for testing, returning its path.
    All callers share the same directory (sequential execution assumed). -/
private def writeTempSpec (content : String) : IO System.FilePath := do
  let dir ← freshTempDir "cli"
  let path := dir / "test.spec.json"
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
  return exitCode == 2 && stderr.length > 0

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
    return exitCode == 2 && hasError

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
  return exitCode == 2 && stderr.contains "unknown command"

def testParseRejectsMaxIterationsWithoutWorker : IO Bool := do
  -- Arrange
  let specContent := "{\"name\": \"bad-combo\", \"maxIterations\": 5, \"criteria\": [{\"description\": \"pass\", \"verify\": {\"type\": \"command\", \"run\": \"true\"}}]}"
  let specPath ← writeTempSpec specContent
  -- Act
  let (exitCode, _, stderr) ← runQed ["parse", specPath.toString]
  -- Assert
  return exitCode == 2 && stderr.contains "maxIterations" && stderr.contains "worker"

def testVerifyDirectoryRunsAllSpecs : IO Bool := do
  -- Arrange
  let dir ← freshTempDir "dir"
  IO.FS.writeFile (dir / "a.spec.json")
    "{\"name\": \"a\", \"criteria\": [{\"description\": \"pass\", \"verify\": {\"type\": \"command\", \"run\": \"true\"}}]}"
  IO.FS.writeFile (dir / "b.spec.json")
    "{\"name\": \"b\", \"criteria\": [{\"description\": \"pass\", \"verify\": {\"type\": \"command\", \"run\": \"true\"}}]}"
  -- Act
  let (exitCode, stdout, _) ← runQed ["verify", dir.toString]
  -- Assert
  return exitCode == 0 && stdout.contains "a" && stdout.contains "b"

def testVerifyDirectoryFailsOnBadSpec : IO Bool := do
  -- Arrange
  let dir ← freshTempDir "dir-fail"
  IO.FS.writeFile (dir / "fail.spec.json")
    "{\"name\": \"fail\", \"criteria\": [{\"description\": \"fails\", \"verify\": {\"type\": \"command\", \"run\": \"false\"}}]}"
  -- Act
  let (exitCode, _, _) ← runQed ["verify", dir.toString]
  -- Assert
  return exitCode == 1

def testVerifyDirectoryFindsNestedSpecs : IO Bool := do
  -- Arrange: create a directory tree with specs at multiple levels
  let dir ← freshTempDir "nested"
  IO.FS.createDirAll (dir / "sub" / "deep")
  IO.FS.createDirAll (dir / ".hidden")
  IO.FS.writeFile (dir / ".qedignore") ".hidden\n"
  IO.FS.writeFile (dir / "root.spec.json")
    "{\"name\": \"root-spec\", \"criteria\": [{\"description\": \"pass\", \"verify\": {\"type\": \"command\", \"run\": \"true\"}}]}"
  IO.FS.writeFile (dir / "sub" / "nested.spec.json")
    "{\"name\": \"nested-spec\", \"criteria\": [{\"description\": \"pass\", \"verify\": {\"type\": \"command\", \"run\": \"true\"}}]}"
  IO.FS.writeFile (dir / "sub" / "deep" / "deep.spec.toml")
    "name = \"deep-spec\"\n\n[[criteria]]\ndescription = \"pass\"\n\n[criteria.verify]\ntype = \"command\"\nrun = \"true\"\n"
  IO.FS.writeFile (dir / ".hidden" / "hidden.spec.json")
    "{\"name\": \"hidden-spec\", \"criteria\": [{\"description\": \"pass\", \"verify\": {\"type\": \"command\", \"run\": \"true\"}}]}"
  -- Act
  let (exitCode, stdout, _) ← runQed ["verify", dir.toString]
  -- Assert: finds root, nested, and deep specs; skips .hidden (via .qedignore)
  return exitCode == 0 && stdout.contains "root-spec" && stdout.contains "nested-spec" &&
    stdout.contains "deep-spec" && !stdout.contains "hidden-spec"

def testVerifyHandlesNonUtf8Output : IO Bool := do
  -- Arrange: command outputs raw bytes that aren't valid UTF-8
  -- Use perl which reliably produces raw bytes on all platforms
  let specContent := "{\"name\": \"non-utf8-test\", \"criteria\": [{\"description\": \"binary output\", \"verify\": {\"type\": \"command\", \"run\": \"perl -e 'print \\\"\\\\x80\\\\xff\\\"'\"}}]}"
  let specPath ← writeTempSpec specContent
  -- Act
  let (exitCode, stdout, _) ← runQed ["verify", specPath.toString]
  -- Assert — should not crash; either pass (if shell handles it) or fail gracefully
  return exitCode == 0 || (exitCode == 1 && stdout.length > 0)

def testLockGeneratesLockFile : IO Bool := do
  -- Arrange: create a directory with a spec that has a lock field
  let dir ← freshTempDir "lock"
  IO.FS.writeFile (dir / "test.spec.json")
    "{\"name\": \"lock-test\", \"criteria\": [{\"description\": \"locked\", \"verify\": {\"type\": \"command\", \"run\": \"true\", \"lock\": [\"*.lean\"]}}]}"
  -- Create a file matching the glob
  IO.FS.writeFile (dir / "test.lean") "-- test\n"
  -- Act: run with cwd set to temp dir so qed.lock is written there, not in the repo root
  let (exitCode, stdout, _) ← runQed ["lock"] (some dir.toString)
  -- Assert
  return exitCode == 0 && stdout.contains "Locked"

def testLockJsonOutputReturnsValidJson : IO Bool := do
  -- Arrange
  let dir ← freshTempDir "lock-json"
  IO.FS.writeFile (dir / "test.spec.json")
    "{\"name\": \"lock-json\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"true\"}}]}"
  -- Act: run with cwd set to temp dir
  let (exitCode, stdout, _) ← runQed ["lock", "--json"] (some dir.toString)
  -- Assert
  match Lean.Json.parse stdout with
  | .error _ => return false
  | .ok json => return exitCode == 0 && (json.getObjVal? "specs").isOk

def testPromoteStripsWorkerSection : IO Bool := do
  -- Arrange
  let specContent := "{\"name\": \"promote-test\", \"worker\": {\"command\": \"echo\"}, \"criteria\": [{\"description\": \"passes\", \"verify\": {\"type\": \"command\", \"run\": \"true\"}}]}"
  let specPath ← writeTempSpec specContent
  -- Act
  let (exitCode, stdout, _) ← runQed ["promote", specPath.toString]
  -- Assert: output is JSON without worker, maxIterations, stuckThreshold
  match Lean.Json.parse stdout with
  | .error _ => return false
  | .ok json =>
    let hasName := (json.getObjValAs? String "name").isOk
    let hasWorker := (json.getObjVal? "worker").isOk
    let hasMaxIter := (json.getObjVal? "maxIterations").isOk
    return exitCode == 0 && hasName && !hasWorker && !hasMaxIter

def testPromoteRejectsVerifyMode : IO Bool := do
  -- Arrange
  let specContent := "{\"name\": \"already-verify\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"true\"}}]}"
  let specPath ← writeTempSpec specContent
  -- Act
  let (exitCode, _, stderr) ← runQed ["promote", specPath.toString]
  -- Assert
  return exitCode == 2 && stderr.contains "already"

def testPromoteWithOutputWritesToFile : IO Bool := do
  -- Arrange
  let specContent := "{\"name\": \"output-test\", \"worker\": {\"command\": \"echo\"}, \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"true\"}}]}"
  let specPath ← writeTempSpec specContent
  let dir ← freshTempDir "promote-output"
  let outputPath := dir / "promoted.spec.json"
  -- Act
  let (exitCode, stdout, _) ← runQed ["promote", specPath.toString, "--output", outputPath.toString]
  -- Assert
  let outputExists ← outputPath.pathExists
  return exitCode == 0 && outputExists && stdout.contains "Promoted"

def testPromoteWithArchiveMovesOriginal : IO Bool := do
  -- Arrange
  let dir ← freshTempDir "promote-archive"
  let specPath := dir / "test.spec.json"
  IO.FS.writeFile specPath
    "{\"name\": \"archive-test\", \"worker\": {\"command\": \"echo\"}, \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"true\"}}]}"
  let outputPath := dir / "promoted.spec.json"
  -- Act
  let (exitCode, _, _) ← runQed ["promote", specPath.toString, "--output", outputPath.toString, "--archive"]
  -- Assert
  let originalExists ← specPath.pathExists
  let archiveExists ← (dir / "archive" / "test.spec.json").pathExists
  return exitCode == 0 && !originalExists && archiveExists

def testVerifyDirectoryRespectsQedignore : IO Bool := do
  -- Arrange: .qedignore excludes "ignored" but not "included"
  let dir ← freshTempDir "qedignore"
  IO.FS.writeFile (dir / ".qedignore") "ignored\n"
  IO.FS.createDirAll (dir / "ignored")
  IO.FS.createDirAll (dir / "included")
  IO.FS.writeFile (dir / "included" / "a.spec.json")
    "{\"name\": \"included-spec\", \"criteria\": [{\"description\": \"pass\", \"verify\": {\"type\": \"command\", \"run\": \"true\"}}]}"
  IO.FS.writeFile (dir / "ignored" / "b.spec.json")
    "{\"name\": \"ignored-spec\", \"criteria\": [{\"description\": \"pass\", \"verify\": {\"type\": \"command\", \"run\": \"true\"}}]}"
  -- Act
  let (exitCode, stdout, _) ← runQed ["verify", dir.toString]
  -- Assert: included-spec found, ignored-spec skipped
  return exitCode == 0 && stdout.contains "included-spec" && !stdout.contains "ignored-spec"

def testVerifyCommandTimeoutEndToEnd : IO Bool := do
  -- Arrange: command sleeps for 10s, timeout is 1s
  let specContent := "{\"name\": \"timeout-test\", \"criteria\": [{\"description\": \"slow\", \"verify\": {\"type\": \"command\", \"run\": \"sleep 10\", \"timeout\": 1}}]}"
  let specPath ← writeTempSpec specContent
  -- Act: use --json to see failure details
  let (exitCode, stdout, _) ← runQed ["verify", "--json", specPath.toString]
  -- Assert: should fail (exit 1) with timeout in JSON details
  return exitCode == 1 && stdout.contains "timed out"

def testParseJsonOutputReturnsFullSpec : IO Bool := do
  -- Arrange
  let specContent := "{\"name\": \"full-parse\", \"criteria\": [{\"description\": \"builds\", \"verify\": {\"type\": \"command\", \"run\": \"make build\"}}]}"
  let specPath ← writeTempSpec specContent
  -- Act
  let (exitCode, stdout, _) ← runQed ["parse", "--json", specPath.toString]
  -- Assert: full spec structure from Serializer, not just summary
  match Lean.Json.parse stdout with
  | .error _ => return false
  | .ok json =>
    let hasName := match json.getObjValAs? String "name" with
      | .ok "full-parse" => true | _ => false
    let hasCriteria := match json.getObjVal? "criteria" with
      | .ok (Lean.Json.arr arr) => arr.size == 1
      | _ => false
    -- Full spec includes nested verify objects with type field
    let hasVerifyType := match json.getObjVal? "criteria" with
      | .ok (Lean.Json.arr arr) => match arr[0]? with
        | some criterion => match criterion.getObjVal? "verify" with
          | .ok verify => match verify.getObjValAs? String "type" with
            | .ok "command" => true | _ => false
          | _ => false
        | none => false
      | _ => false
    return exitCode == 0 && hasName && hasCriteria && hasVerifyType

def testLockJsonOutputReturnsFullLockFile : IO Bool := do
  -- Arrange: spec with lock patterns and a matching file
  let dir ← freshTempDir "lock-full-json"
  IO.FS.writeFile (dir / "test.spec.json")
    "{\"name\": \"lock-full\", \"criteria\": [{\"description\": \"locked\", \"verify\": {\"type\": \"command\", \"run\": \"true\", \"lock\": [\"*.txt\"]}}]}"
  IO.FS.writeFile (dir / "data.txt") "content\n"
  -- Act
  let (exitCode, stdout, _) ← runQed ["lock", "--json"] (some dir.toString)
  -- Assert: full lock file structure with version, specs array, and artifacts
  match Lean.Json.parse stdout with
  | .error _ => return false
  | .ok json =>
    let hasVersion := match json.getObjValAs? Nat "version" with
      | .ok 1 => true | _ => false
    let hasSpecs := match json.getObjVal? "specs" with
      | .ok (Lean.Json.arr arr) => arr.size == 1
      | _ => false
    let hasArtifacts := stdout.contains "\"artifacts\""
    let hasHash := stdout.contains "\"hash\""
    return exitCode == 0 && hasVersion && hasSpecs && hasArtifacts && hasHash

def testVerifyDirectoryJsonOutputReturnsArray : IO Bool := do
  -- Arrange
  let dir ← freshTempDir "dir-json"
  IO.FS.writeFile (dir / "a.spec.json")
    "{\"name\": \"a\", \"criteria\": [{\"description\": \"pass\", \"verify\": {\"type\": \"command\", \"run\": \"true\"}}]}"
  IO.FS.writeFile (dir / "b.spec.json")
    "{\"name\": \"b\", \"criteria\": [{\"description\": \"pass\", \"verify\": {\"type\": \"command\", \"run\": \"true\"}}]}"
  -- Act
  let (exitCode, stdout, _) ← runQed ["verify", "--json", dir.toString]
  -- Assert: single JSON object wrapping all specs
  match Lean.Json.parse stdout with
  | .error _ => return false
  | .ok json =>
    let hasSpecs := match json.getObjVal? "specs" with
      | .ok (Lean.Json.arr arr) => arr.size == 2
      | _ => false
    let hasPassed := match json.getObjValAs? Bool "passed" with
      | .ok true => true | _ => false
    return exitCode == 0 && hasSpecs && hasPassed

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
  ("testUnknownCommandReturnsError", testUnknownCommandReturnsError),
  ("testParseRejectsMaxIterationsWithoutWorker", testParseRejectsMaxIterationsWithoutWorker),
  ("testVerifyDirectoryRunsAllSpecs", testVerifyDirectoryRunsAllSpecs),
  ("testVerifyDirectoryFailsOnBadSpec", testVerifyDirectoryFailsOnBadSpec),
  ("testVerifyDirectoryFindsNestedSpecs", testVerifyDirectoryFindsNestedSpecs),
  ("testVerifyHandlesNonUtf8Output", testVerifyHandlesNonUtf8Output),
  ("testVerifyCommandTimeoutEndToEnd", testVerifyCommandTimeoutEndToEnd),
  ("testLockGeneratesLockFile", testLockGeneratesLockFile),
  ("testLockJsonOutputReturnsValidJson", testLockJsonOutputReturnsValidJson),
  ("testPromoteStripsWorkerSection", testPromoteStripsWorkerSection),
  ("testPromoteRejectsVerifyMode", testPromoteRejectsVerifyMode),
  ("testPromoteWithOutputWritesToFile", testPromoteWithOutputWritesToFile),
  ("testPromoteWithArchiveMovesOriginal", testPromoteWithArchiveMovesOriginal),
  ("testVerifyDirectoryRespectsQedignore", testVerifyDirectoryRespectsQedignore),
  ("testParseJsonOutputReturnsFullSpec", testParseJsonOutputReturnsFullSpec),
  ("testLockJsonOutputReturnsFullLockFile", testLockJsonOutputReturnsFullLockFile),
  ("testVerifyDirectoryJsonOutputReturnsArray", testVerifyDirectoryJsonOutputReturnsArray)
]
