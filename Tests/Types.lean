import Qed

open Qed

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

def typeTests : List (String × IO Bool) := [
  ("testLoopConfigDefaultMaxIterationsIsTen", testLoopConfigDefaultMaxIterationsIsTen),
  ("testLoopConfigDefaultStuckThresholdIsThree", testLoopConfigDefaultStuckThresholdIsThree),
  ("testLoopStatePassedIsTerminal", testLoopStatePassedIsTerminal),
  ("testLoopStateStuckIsTerminal", testLoopStateStuckIsTerminal),
  ("testLoopStateReadyIsNotTerminal", testLoopStateReadyIsNotTerminal),
  ("testLoopStateWorkerRunningIsNotTerminal", testLoopStateWorkerRunningIsNotTerminal),
  ("testCiScheduleDefaultsToAlwaysForCommand", testCiScheduleDefaultsToAlwaysForCommand),
  ("testCiScheduleDefaultsToManualForHuman", testCiScheduleDefaultsToManualForHuman)
]
