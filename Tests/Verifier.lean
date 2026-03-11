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

def testVerifyHumanFailsInNonInteractiveContext : IO Bool := do
  -- Arrange: in test context, stdin is non-interactive
  let criterion : AcceptanceCriterion := {
    description := "manual check"
    verify := .human "Please verify the UI looks correct"
  }
  -- Act
  let result ← verifyCriterion criterion
  -- Assert: human criteria fail with "non-interactive context" when stdin is piped
  match result with
  | .fail details => return details == "non-interactive context"
  | _ => return false

def testVerifySkipReturnsSkippedWithReason : IO Bool := do
  -- Arrange
  let criterion : AcceptanceCriterion := {
    description := "skipped check"
    verify := .command "true"
    skip := some "not yet implemented"
  }
  -- Act
  let result ← verifyCriterion criterion
  -- Assert: skip field produces .skipped with the reason string
  match result with
  | .skipped reason => return reason == "not yet implemented"
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
  let thirdNonInteractive := match results[2]? with
    | some (_, r) => match r with
      | .fail details => details == "non-interactive context"
      | _ => false
    | none => false
  return descriptions == ["passes", "fails", "manual"] &&
    firstPassed && secondFailed && thirdNonInteractive

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

def testParseAgentVerdictHandlesTrailingContent : IO Bool := do
  -- Arrange: agent produces text after the closing backticks
  let response := "Analysis:\n```json\n{\"pass\": true}\n```\nHope that helps!"
  -- Act / Assert
  match Verifier.parseAgentVerdict response with
  | .ok true => return true
  | _ => return false

def testParseAgentVerdictErrorOnMissingPassField : IO Bool := do
  -- Arrange: JSON block without "pass" field
  let response := "Review done.\n```json\n{\"result\": \"ok\"}\n```"
  -- Act / Assert
  match Verifier.parseAgentVerdict response with
  | .error _ => return true
  | _ => return false

def testVerifyCommandTimesOutSlowProcess : IO Bool := do
  -- Arrange: command sleeps for 10s, timeout is 1s
  let criterion : AcceptanceCriterion := {
    description := "slow command"
    verify := .command "sleep 10" (timeout := 1)
  }
  -- Act
  let result ← verifyCriterion criterion
  -- Assert: should fail with timeout message
  match result with
  | .fail details => return details.contains "timed out"
  | _ => return false

def testVerifyCommandCompletesBeforeTimeout : IO Bool := do
  -- Arrange: command completes instantly, generous timeout
  let criterion : AcceptanceCriterion := {
    description := "fast command"
    verify := .command "echo done" (timeout := 60)
  }
  -- Act
  let result ← verifyCriterion criterion
  -- Assert: should pass normally
  match result with
  | .pass details => return details.contains "done"
  | _ => return false

def testVerifyCommandTimeoutCapturesPartialOutput : IO Bool := do
  -- Arrange: command produces output then sleeps
  let criterion : AcceptanceCriterion := {
    description := "partial output"
    verify := .command "echo partial-output-before-timeout && sleep 10" (timeout := 1)
  }
  -- Act
  let result ← verifyCriterion criterion
  -- Assert: should fail with timeout but include partial stdout
  match result with
  | .fail details => return details.contains "timed out" && details.contains "partial-output-before-timeout"
  | _ => return false

-- Pure function tests

def testTargetToModuleExtractsModule : IO Bool := do
  -- Arrange / Act / Assert
  return targetToModule "Qed.Proofs.Termination.loop_terminates" == some "Qed.Proofs.Termination"

def testTargetToModuleSingleDot : IO Bool := do
  -- Arrange / Act / Assert
  return targetToModule "Module.theorem" == some "Module"

def testTargetToModuleRejectsNoDot : IO Bool := do
  -- Arrange / Act / Assert
  return targetToModule "nodot" == none

def testTargetToModuleRejectsEmpty : IO Bool := do
  -- Arrange / Act / Assert
  return targetToModule "" == none

def testModuleToPathConverts : IO Bool := do
  -- Arrange / Act / Assert
  return moduleToPath "Qed.Proofs.Termination" == "Qed/Proofs/Termination.lean"

def testModuleToPathSingleSegment : IO Bool := do
  -- Arrange / Act / Assert
  return moduleToPath "Main" == "Main.lean"

def testIsValidModuleNameAcceptsValid : IO Bool := do
  -- Arrange / Act / Assert
  return isValidModuleName "Qed.Proofs.Termination"

def testIsValidModuleNameRejectsShellInjection : IO Bool := do
  -- Arrange / Act / Assert
  return !isValidModuleName "Qed; rm -rf /"

def testIsValidModuleNameRejectsEmpty : IO Bool := do
  -- Arrange / Act / Assert
  return !isValidModuleName ""

def testIsValidModuleNameRejectsDoubleDot : IO Bool := do
  -- Arrange / Act / Assert
  return !isValidModuleName "Qed..Proofs"

def testContainsPlaceholderDetectsStandalone : IO Bool := do
  -- Arrange / Act / Assert
  return containsPlaceholder "theorem foo : True := sorry"

def testContainsPlaceholderIgnoresInsideIdentifier : IO Bool := do
  -- Arrange / Act / Assert
  return !containsPlaceholder "def sorryHandler := 42"

def testContainsPlaceholderDetectsInStringLiteral : IO Bool := do
  -- Arrange / Act / Assert
  -- Word boundary check flags this — acceptable false positive for proof files
  return containsPlaceholder "let msg := \"no sorry here\""

def testContainsPlaceholderDetectsAtStartOfFile : IO Bool := do
  -- Arrange / Act / Assert
  return containsPlaceholder "sorry\ntheorem foo : True := by trivial"

def testContainsPlaceholderDetectsAtEndOfFile : IO Bool := do
  -- Arrange / Act / Assert
  return containsPlaceholder "theorem foo : True := sorry"

def testContainsPlaceholderCleanFile : IO Bool := do
  -- Arrange / Act / Assert
  return !containsPlaceholder "theorem foo : True := by trivial\ndef bar := 42"

def verifierTests : List (String × IO Bool) := [
  ("testVerifyCommandReturnsPassOnExitZero", testVerifyCommandReturnsPassOnExitZero),
  ("testVerifyCommandReturnsFailOnNonZeroExit", testVerifyCommandReturnsFailOnNonZeroExit),
  ("testVerifyCommandCapturesStdout", testVerifyCommandCapturesStdout),
  ("testVerifyCommandCapturesStderr", testVerifyCommandCapturesStderr),
  ("testVerifyCommandHandlesPipedCommands", testVerifyCommandHandlesPipedCommands),
  ("testVerifyCommandReturnsFailForMissingCommand", testVerifyCommandReturnsFailForMissingCommand),
  ("testVerifyHumanFailsInNonInteractiveContext", testVerifyHumanFailsInNonInteractiveContext),
  ("testVerifySkipReturnsSkippedWithReason", testVerifySkipReturnsSkippedWithReason),
  ("testVerifyAllReturnsResultsForAllCriteria", testVerifyAllReturnsResultsForAllCriteria),
  ("testParseAgentVerdictPassWithJsonBlock", testParseAgentVerdictPassWithJsonBlock),
  ("testParseAgentVerdictFailWithJsonBlock", testParseAgentVerdictFailWithJsonBlock),
  ("testParseAgentVerdictUsesLastJsonBlock", testParseAgentVerdictUsesLastJsonBlock),
  ("testParseAgentVerdictFallbackToRawJson", testParseAgentVerdictFallbackToRawJson),
  ("testParseAgentVerdictErrorOnNoVerdict", testParseAgentVerdictErrorOnNoVerdict),
  ("testParseAgentVerdictHandlesTrailingContent", testParseAgentVerdictHandlesTrailingContent),
  ("testParseAgentVerdictErrorOnMissingPassField", testParseAgentVerdictErrorOnMissingPassField),
  ("testVerifyCommandTimesOutSlowProcess", testVerifyCommandTimesOutSlowProcess),
  ("testVerifyCommandCompletesBeforeTimeout", testVerifyCommandCompletesBeforeTimeout),
  ("testVerifyCommandTimeoutCapturesPartialOutput", testVerifyCommandTimeoutCapturesPartialOutput),
  ("testTargetToModuleExtractsModule", testTargetToModuleExtractsModule),
  ("testTargetToModuleSingleDot", testTargetToModuleSingleDot),
  ("testTargetToModuleRejectsNoDot", testTargetToModuleRejectsNoDot),
  ("testTargetToModuleRejectsEmpty", testTargetToModuleRejectsEmpty),
  ("testModuleToPathConverts", testModuleToPathConverts),
  ("testModuleToPathSingleSegment", testModuleToPathSingleSegment),
  ("testIsValidModuleNameAcceptsValid", testIsValidModuleNameAcceptsValid),
  ("testIsValidModuleNameRejectsShellInjection", testIsValidModuleNameRejectsShellInjection),
  ("testIsValidModuleNameRejectsEmpty", testIsValidModuleNameRejectsEmpty),
  ("testIsValidModuleNameRejectsDoubleDot", testIsValidModuleNameRejectsDoubleDot),
  ("testContainsPlaceholderDetectsStandalone", testContainsPlaceholderDetectsStandalone),
  ("testContainsPlaceholderIgnoresInsideIdentifier", testContainsPlaceholderIgnoresInsideIdentifier),
  ("testContainsPlaceholderDetectsInStringLiteral", testContainsPlaceholderDetectsInStringLiteral),
  ("testContainsPlaceholderDetectsAtStartOfFile", testContainsPlaceholderDetectsAtStartOfFile),
  ("testContainsPlaceholderDetectsAtEndOfFile", testContainsPlaceholderDetectsAtEndOfFile),
  ("testContainsPlaceholderCleanFile", testContainsPlaceholderCleanFile)
]
