import Qed
import Qed.Verifier

open Qed
open Qed.Verifier

def testVerifyCommandReturnsPassOnExitZero : IO Bool := do
  -- Arrange
  let criterion : AcceptanceCriterion := {
    description := "runs true"
    verify := .command "true"
  }
  -- Act
  let result ← verifyCriterion criterion
  -- Assert
  return result.isPassed

def testVerifyCommandReturnsFailOnNonZeroExit : IO Bool := do
  -- Arrange
  let criterion : AcceptanceCriterion := {
    description := "runs false"
    verify := .command "false"
  }
  -- Act
  let result ← verifyCriterion criterion
  -- Assert
  return result.isFailed

def testVerifyCommandCapturesStdout : IO Bool := do
  -- Arrange
  let criterion : AcceptanceCriterion := {
    description := "echoes hello"
    verify := .command "echo hello"
  }
  -- Act
  let result ← verifyCriterion criterion
  -- Assert
  match result with
  | .pass details => return details.contains "hello"
  | _ => return false

def testVerifyCommandCapturesStderr : IO Bool := do
  -- Arrange
  let criterion : AcceptanceCriterion := {
    description := "writes to stderr"
    verify := .command "echo error >&2"
  }
  -- Act
  let result ← verifyCriterion criterion
  -- Assert
  match result with
  | .pass details => return details.contains "error" && details.contains "STDERR"
  | _ => return false

def testVerifyCommandHandlesPipedCommands : IO Bool := do
  -- Arrange
  let criterion : AcceptanceCriterion := {
    description := "pipes work"
    verify := .command "echo hello | grep hello"
  }
  -- Act
  let result ← verifyCriterion criterion
  -- Assert
  return result.isPassed

def testVerifyCommandReturnsFailForMissingCommand : IO Bool := do
  -- Arrange
  let criterion : AcceptanceCriterion := {
    description := "runs nonexistent command"
    verify := .command "this_command_does_not_exist_qed_test_2024"
  }
  -- Act
  let result ← verifyCriterion criterion
  -- Assert
  return result.isFailed

def testVerifyHumanReturnsNeedsHuman : IO Bool := do
  -- Arrange
  let instruction := "Please verify the UI looks correct"
  let criterion : AcceptanceCriterion := {
    description := "manual check"
    verify := .human instruction
  }
  -- Act
  let result ← verifyCriterion criterion
  -- Assert
  match result with
  | .needsHuman returnedInstruction => return returnedInstruction == instruction
  | _ => return false

def testVerifyAllReturnsResultsForAllCriteria : IO Bool := do
  -- Arrange
  let criteria : List AcceptanceCriterion := [
    { description := "passes", verify := .command "true" },
    { description := "fails", verify := .command "false" },
    { description := "manual", verify := .human "check it" }
  ]
  -- Act
  let results ← verifyAll criteria
  -- Assert
  if results.length != 3 then return false
  let descriptions := results.map (·.1)
  let firstPassed := match results[0]? with
    | some (_, r) => r.isPassed
    | none => false
  let secondFailed := match results[1]? with
    | some (_, r) => r.isFailed
    | none => false
  let thirdHuman := match results[2]? with
    | some (_, .needsHuman _) => true
    | _ => false
  return descriptions == ["passes", "fails", "manual"] &&
    firstPassed && secondFailed && thirdHuman

def verifierTests : List (String × IO Bool) := [
  ("testVerifyCommandReturnsPassOnExitZero", testVerifyCommandReturnsPassOnExitZero),
  ("testVerifyCommandReturnsFailOnNonZeroExit", testVerifyCommandReturnsFailOnNonZeroExit),
  ("testVerifyCommandCapturesStdout", testVerifyCommandCapturesStdout),
  ("testVerifyCommandCapturesStderr", testVerifyCommandCapturesStderr),
  ("testVerifyCommandHandlesPipedCommands", testVerifyCommandHandlesPipedCommands),
  ("testVerifyCommandReturnsFailForMissingCommand", testVerifyCommandReturnsFailForMissingCommand),
  ("testVerifyHumanReturnsNeedsHuman", testVerifyHumanReturnsNeedsHuman),
  ("testVerifyAllReturnsResultsForAllCriteria", testVerifyAllReturnsResultsForAllCriteria)
]
