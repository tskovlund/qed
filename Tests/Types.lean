import Qed

open Qed

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

def typeTests : List (String × IO Bool) := [
  ("testLoopStatePassedIsTerminal", testLoopStatePassedIsTerminal),
  ("testLoopStateStuckIsTerminal", testLoopStateStuckIsTerminal),
  ("testLoopStateReadyIsNotTerminal", testLoopStateReadyIsNotTerminal),
  ("testLoopStateWorkerRunningIsNotTerminal", testLoopStateWorkerRunningIsNotTerminal)
]
