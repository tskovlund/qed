import Qed

open Qed

def testIsValidGlobPatternAcceptsSimplePatterns : IO Bool := do
  -- Arrange / Act / Assert
  return ContractLock.isValidGlobPattern "*.lean" &&
    ContractLock.isValidGlobPattern "Tests/**/*.lean" &&
    ContractLock.isValidGlobPattern "src/main.py" &&
    ContractLock.isValidGlobPattern "dir/[abc].txt"

def testIsValidGlobPatternRejectsUnsafePatterns : IO Bool := do
  -- Arrange / Act / Assert
  return !ContractLock.isValidGlobPattern "$(whoami)" &&
    !ContractLock.isValidGlobPattern "foo;rm -rf /" &&
    !ContractLock.isValidGlobPattern "a|b" &&
    !ContractLock.isValidGlobPattern "" &&
    !ContractLock.isValidGlobPattern "foo`bar`"

def testExtractTheoremStatementFindsSimpleTheorem : IO Bool := do
  -- Arrange
  let source := "theorem foo (x : Nat) : x + 0 = x := by\n  simp\n"
  -- Act
  let result := ContractLock.extractTheoremStatement source "foo"
  -- Assert
  match result with
  | some statement => return statement.contains "theorem foo" && statement.contains "x + 0 = x"
  | none => return false

def testExtractTheoremStatementFindsPrivateTheorem : IO Bool := do
  -- Arrange
  let source := "private theorem bar : True := by\n  trivial\n"
  -- Act
  let result := ContractLock.extractTheoremStatement source "bar"
  -- Assert
  match result with
  | some statement => return statement.contains "private theorem bar" && statement.contains "True"
  | none => return false

def testExtractTheoremStatementHandlesMultiLine : IO Bool := do
  -- Arrange
  let source := "theorem multi_line\n    (x : Nat) (y : Nat)\n    (h : x < y) : x + 1 ≤ y := by\n  omega\n"
  -- Act
  let result := ContractLock.extractTheoremStatement source "multi_line"
  -- Assert
  match result with
  | some statement =>
    return statement.contains "theorem multi_line" &&
      statement.contains "x + 1 ≤ y"
  | none => return false

def testExtractTheoremStatementReturnsNoneForMissing : IO Bool := do
  -- Arrange
  let source := "def foo : Nat := 42\n"
  -- Act
  let result := ContractLock.extractTheoremStatement source "nonexistent"
  -- Assert
  return result.isNone

def testExtractTheoremStatementExcludesProofBody : IO Bool := do
  -- Arrange
  let source := "theorem excludes_body : 1 + 1 = 2 := by\n  rfl\n"
  -- Act
  let result := ContractLock.extractTheoremStatement source "excludes_body"
  -- Assert
  match result with
  | some statement => return !statement.contains "rfl" && !statement.contains ":="
  | none => return false

def testShortTheoremNameExtractsLastSegment : IO Bool := do
  -- Arrange / Act / Assert
  return ContractLock.shortTheoremName "Qed.Proofs.Foo.bar" == "bar" &&
    ContractLock.shortTheoremName "simple" == "simple"

def testLockFileRoundtrip : IO Bool := do
  -- Arrange
  let lockFile : ContractLock.LockFile := {
    version := 1
    specs := [{
      specPath := "specs/test.spec.json"
      criteria := [{
        description := "test criterion"
        artifacts := [
          { path := "src/main.lean", hash := "abc123" },
          { path := "theorem:Foo.bar", hash := "def456" }
        ]
      }]
    }]
  }
  -- Act: serialize then parse
  let serialized := ContractLock.serializeLockFile lockFile
  let parsed := ContractLock.parseLockFile serialized
  -- Assert
  match parsed with
  | .ok result =>
    match result.specs with
    | [specLock] =>
      match specLock.criteria with
      | [criterionLock] =>
        match criterionLock.artifacts with
        | [a1, a2] =>
          return result.version == 1 &&
            specLock.specPath == "specs/test.spec.json" &&
            criterionLock.description == "test criterion" &&
            a1.path == "src/main.lean" && a1.hash == "abc123" &&
            a2.path == "theorem:Foo.bar" && a2.hash == "def456"
        | _ => return false
      | _ => return false
    | _ => return false
  | .error _ => return false

def testParseLockFileRejectsInvalidVersion : IO Bool := do
  -- Arrange
  let json := "{\"version\": 99, \"specs\": []}"
  -- Act
  let result := ContractLock.parseLockFile json
  -- Assert
  match result with
  | .ok _ => return false
  | .error e => return e.contains "version"

def testParseLockFileRejectsInvalidJson : IO Bool := do
  -- Arrange
  let json := "not json"
  -- Act
  let result := ContractLock.parseLockFile json
  -- Assert
  match result with
  | .ok _ => return false
  | .error _ => return true

def testExtractTheoremStatementHandlesWhereClause : IO Bool := do
  -- Arrange — theorem using `where` instead of `:=` for the proof
  let source := "theorem uses_where (x : Nat) : x = x\n    where\n  foo := rfl\n"
  -- Act
  let result := ContractLock.extractTheoremStatement source "uses_where"
  -- Assert
  match result with
  | some statement =>
    return statement.contains "theorem uses_where" &&
      statement.contains "x = x" &&
      !statement.contains "foo" &&
      !statement.contains "rfl"
  | none => return false

def contractLockTests : List (String × IO Bool) := [
  ("testIsValidGlobPatternAcceptsSimplePatterns", testIsValidGlobPatternAcceptsSimplePatterns),
  ("testIsValidGlobPatternRejectsUnsafePatterns", testIsValidGlobPatternRejectsUnsafePatterns),
  ("testExtractTheoremStatementFindsSimpleTheorem", testExtractTheoremStatementFindsSimpleTheorem),
  ("testExtractTheoremStatementFindsPrivateTheorem", testExtractTheoremStatementFindsPrivateTheorem),
  ("testExtractTheoremStatementHandlesMultiLine", testExtractTheoremStatementHandlesMultiLine),
  ("testExtractTheoremStatementReturnsNoneForMissing", testExtractTheoremStatementReturnsNoneForMissing),
  ("testExtractTheoremStatementExcludesProofBody", testExtractTheoremStatementExcludesProofBody),
  ("testExtractTheoremStatementHandlesWhereClause", testExtractTheoremStatementHandlesWhereClause),
  ("testShortTheoremNameExtractsLastSegment", testShortTheoremNameExtractsLastSegment),
  ("testLockFileRoundtrip", testLockFileRoundtrip),
  ("testParseLockFileRejectsInvalidVersion", testParseLockFileRejectsInvalidVersion),
  ("testParseLockFileRejectsInvalidJson", testParseLockFileRejectsInvalidJson)
]
