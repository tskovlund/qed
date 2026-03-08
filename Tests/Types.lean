import Qed

open Qed

def testIsTerminalReturnsTrueForPassed : IO Bool := do
  -- Arrange
  let state := LoopState.passed 3
  -- Act / Assert
  return state.isTerminal

def testIsTerminalReturnsTrueForStuck : IO Bool := do
  -- Arrange
  let state := LoopState.stuck 3 ["test"]
  -- Act / Assert
  return state.isTerminal

def testIsTerminalReturnsFalseForReady : IO Bool := do
  -- Arrange
  let state := LoopState.ready
  -- Act / Assert
  return !state.isTerminal

def testIsTerminalReturnsFalseForWorkerRunning : IO Bool := do
  -- Arrange
  let state := LoopState.workerRunning 1
  -- Act / Assert
  return !state.isTerminal

def typeTests : List (String × IO Bool) := [
  ("testIsTerminalReturnsTrueForPassed", testIsTerminalReturnsTrueForPassed),
  ("testIsTerminalReturnsTrueForStuck", testIsTerminalReturnsTrueForStuck),
  ("testIsTerminalReturnsFalseForReady", testIsTerminalReturnsFalseForReady),
  ("testIsTerminalReturnsFalseForWorkerRunning", testIsTerminalReturnsFalseForWorkerRunning)
]
