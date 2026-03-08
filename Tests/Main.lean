import Qed

open Qed

/-- Run a named test, print result, return whether it passed. -/
def runTest (name : String) (test : IO Bool) : IO Bool := do
  let passed ← test
  if passed then
    IO.println s!"PASS: {name}"
  else
    IO.eprintln s!"FAIL: {name}"
  return passed

def testVerifyTypeCommandHasCorrectRun : IO Bool := do
  -- Arrange
  let verifyType := VerifyType.command "make test"
  -- Act
  let commandRun := match verifyType with
    | .command run _ => some run
    | _ => none
  -- Assert
  return commandRun == some "make test"

def testAcceptanceCriterionStoresDescription : IO Bool := do
  -- Arrange
  let criterion : AcceptanceCriterion := {
    description := "All tests pass"
    verify := VerifyType.command "make test"
  }
  -- Act / Assert
  return criterion.description == "All tests pass"

def testLoopConfigDefaultMaxIterationsIsTen : IO Bool := do
  -- Arrange
  let config : LoopConfig := {}
  -- Act / Assert
  return config.maxIterations == 10

def testLoopConfigDefaultStuckThresholdIsThree : IO Bool := do
  -- Arrange
  let config : LoopConfig := {}
  -- Act / Assert
  return config.stuckThreshold == 3

def testSpecWorkerLoopModeHasWorker : IO Bool := do
  -- Arrange
  let spec : Spec := {
    name := "test-task"
    mode := .workerLoop { command := "echo hello" } {}
    criteria := []
  }
  -- Act / Assert
  return match spec.mode with
    | .workerLoop worker _ => worker.command == "echo hello"
    | .verify => false

def testSpecVerifyModeHasNoWorker : IO Bool := do
  -- Arrange
  let criterion : AcceptanceCriterion := {
    description := "test"
    verify := VerifyType.command "echo"
  }
  let spec : Spec := {
    name := "test-task"
    mode := .verify
    criteria := [criterion]
  }
  -- Act / Assert
  return match spec.mode with
    | .workerLoop _ _ => false
    | .verify => true

def testLoopStatePassedIsTerminal : IO Bool := do
  -- Arrange
  let state := LoopState.passed 3
  -- Act / Assert
  return state.isTerminal

def testLoopStateStuckIsTerminal : IO Bool := do
  -- Arrange
  let state := LoopState.stuck 3 ["test"]
  -- Act / Assert
  return state.isTerminal

def testLoopStateReadyIsNotTerminal : IO Bool := do
  -- Arrange
  let state := LoopState.ready
  -- Act / Assert
  return !state.isTerminal

def testLoopStateWorkerRunningIsNotTerminal : IO Bool := do
  -- Arrange
  let state := LoopState.workerRunning 1
  -- Act / Assert
  return !state.isTerminal

def testVerificationResultPassIsPassed : IO Bool := do
  -- Arrange
  let result := VerificationResult.pass "ok"
  -- Act / Assert
  return result.isPassed

def testVerificationResultFailIsFailed : IO Bool := do
  -- Arrange
  let result := VerificationResult.fail "error"
  -- Act / Assert
  return result.isFailed

def testCiScheduleDefaultsToAlwaysForCommand : IO Bool := do
  -- Arrange
  let criterion : AcceptanceCriterion := {
    description := "test"
    verify := VerifyType.command "echo"
  }
  -- Act / Assert
  return criterion.ci == CiSchedule.always

def testCiScheduleDefaultsToManualForHuman : IO Bool := do
  -- Arrange
  let criterion : AcceptanceCriterion := {
    description := "test"
    verify := VerifyType.human "check visually"
  }
  -- Act / Assert
  return criterion.ci == CiSchedule.manual

def main : IO UInt32 := do
  let tests : List (String × IO Bool) := [
    ("testVerifyTypeCommandHasCorrectRun", testVerifyTypeCommandHasCorrectRun),
    ("testAcceptanceCriterionStoresDescription", testAcceptanceCriterionStoresDescription),
    ("testLoopConfigDefaultMaxIterationsIsTen", testLoopConfigDefaultMaxIterationsIsTen),
    ("testLoopConfigDefaultStuckThresholdIsThree", testLoopConfigDefaultStuckThresholdIsThree),
    ("testSpecWorkerLoopModeHasWorker", testSpecWorkerLoopModeHasWorker),
    ("testSpecVerifyModeHasNoWorker", testSpecVerifyModeHasNoWorker),
    ("testLoopStatePassedIsTerminal", testLoopStatePassedIsTerminal),
    ("testLoopStateStuckIsTerminal", testLoopStateStuckIsTerminal),
    ("testLoopStateReadyIsNotTerminal", testLoopStateReadyIsNotTerminal),
    ("testLoopStateWorkerRunningIsNotTerminal", testLoopStateWorkerRunningIsNotTerminal),
    ("testVerificationResultPassIsPassed", testVerificationResultPassIsPassed),
    ("testVerificationResultFailIsFailed", testVerificationResultFailIsFailed),
    ("testCiScheduleDefaultsToAlwaysForCommand", testCiScheduleDefaultsToAlwaysForCommand),
    ("testCiScheduleDefaultsToManualForHuman", testCiScheduleDefaultsToManualForHuman)
  ]

  let mut failedCount : Nat := 0
  for (name, test) in tests do
    let passed ← runTest name test
    if !passed then
      failedCount := failedCount + 1

  IO.println ""
  if failedCount > 0 then
    IO.eprintln s!"{failedCount} test(s) failed"
    return 1
  else
    IO.println s!"All {tests.length} tests passed"
    return 0
