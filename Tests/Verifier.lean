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

def testParseAgentVerdictPassWithJsonBlock : IO Bool := do
  -- Arrange
  let response := "The code looks correct.\n```json\n{\"pass\": true}\n```"
  -- Act / Assert
  match Verifier.parseAgentVerdict response with
  | .ok true => return true
  | _ => return false

def testParseAgentVerdictFailWithJsonBlock : IO Bool := do
  -- Arrange
  let response := "Found issues.\n```json\n{\"pass\": false, \"reason\": \"missing error handling\"}\n```"
  -- Act / Assert
  match Verifier.parseAgentVerdict response with
  | .ok false => return true
  | _ => return false

def testParseAgentVerdictUsesLastJsonBlock : IO Bool := do
  -- Arrange: agent might show example JSON blocks before the verdict
  let response := "Here's an example:\n```json\n{\"example\": true}\n```\nMy verdict:\n```json\n{\"pass\": true}\n```"
  -- Act / Assert
  match Verifier.parseAgentVerdict response with
  | .ok true => return true
  | _ => return false

def testParseAgentVerdictFallbackToRawJson : IO Bool := do
  -- Arrange: no ```json block, but a raw JSON line with "pass"
  let response := "Analysis complete.\n{\"pass\": true}"
  -- Act / Assert
  match Verifier.parseAgentVerdict response with
  | .ok true => return true
  | _ => return false

def testParseAgentVerdictErrorOnNoVerdict : IO Bool := do
  -- Arrange: no verdict at all
  let response := "The code looks fine to me. Everything is great."
  -- Act / Assert
  match Verifier.parseAgentVerdict response with
  | .error _ => return true
  | _ => return false

def testParseAgentVerdictErrorOnMissingPassField : IO Bool := do
  -- Arrange: JSON block without "pass" field
  let response := "Review done.\n```json\n{\"result\": \"ok\"}\n```"
  -- Act / Assert
  match Verifier.parseAgentVerdict response with
  | .error _ => return true
  | _ => return false

def verifierTests : List (String × IO Bool) := [
  ("testVerifyCommandReturnsPassOnExitZero", testVerifyCommandReturnsPassOnExitZero),
  ("testVerifyCommandReturnsFailOnNonZeroExit", testVerifyCommandReturnsFailOnNonZeroExit),
  ("testVerifyCommandCapturesStdout", testVerifyCommandCapturesStdout),
  ("testVerifyCommandCapturesStderr", testVerifyCommandCapturesStderr),
  ("testVerifyCommandHandlesPipedCommands", testVerifyCommandHandlesPipedCommands),
  ("testVerifyCommandReturnsFailForMissingCommand", testVerifyCommandReturnsFailForMissingCommand),
  ("testVerifyHumanReturnsNeedsHuman", testVerifyHumanReturnsNeedsHuman),
  ("testVerifyAllReturnsResultsForAllCriteria", testVerifyAllReturnsResultsForAllCriteria),
  ("testParseAgentVerdictPassWithJsonBlock", testParseAgentVerdictPassWithJsonBlock),
  ("testParseAgentVerdictFailWithJsonBlock", testParseAgentVerdictFailWithJsonBlock),
  ("testParseAgentVerdictUsesLastJsonBlock", testParseAgentVerdictUsesLastJsonBlock),
  ("testParseAgentVerdictFallbackToRawJson", testParseAgentVerdictFallbackToRawJson),
  ("testParseAgentVerdictErrorOnNoVerdict", testParseAgentVerdictErrorOnNoVerdict),
  ("testParseAgentVerdictErrorOnMissingPassField", testParseAgentVerdictErrorOnMissingPassField)
]
