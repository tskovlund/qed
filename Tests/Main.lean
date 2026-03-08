import Qed

open Qed

def main : IO UInt32 := do
  let mut failed : Nat := 0

  -- Test: VerifyType constructors
  let cmd := VerifyType.command "make test"
  match cmd with
  | .command run _ =>
    if run != "make test" then
      IO.eprintln "FAIL: command run should be 'make test'"
      failed := failed + 1
    else
      IO.println "PASS: VerifyType.command construction"
  | _ =>
    IO.eprintln "FAIL: expected VerifyType.command"
    failed := failed + 1

  -- Test: AcceptanceCriterion construction
  let criterion : AcceptanceCriterion := {
    description := "All tests pass"
    verify := VerifyType.command "make test"
  }
  if criterion.description != "All tests pass" then
    IO.eprintln "FAIL: criterion description mismatch"
    failed := failed + 1
  else
    IO.println "PASS: AcceptanceCriterion construction"

  -- Test: Spec construction with defaults
  let spec : Spec := {
    name := "test-task"
    worker := { command := "echo hello" }
    criteria := [criterion]
  }
  if spec.maxIterations != 10 then
    IO.eprintln s!"FAIL: default maxIterations should be 10, got {spec.maxIterations}"
    failed := failed + 1
  else
    IO.println "PASS: Spec default maxIterations"

  if spec.stuckThreshold != 3 then
    IO.eprintln s!"FAIL: default stuckThreshold should be 3, got {spec.stuckThreshold}"
    failed := failed + 1
  else
    IO.println "PASS: Spec default stuckThreshold"

  -- Test: LoopState.isTerminal
  if !LoopState.isTerminal (.passed 3) then
    IO.eprintln "FAIL: passed should be terminal"
    failed := failed + 1
  else
    IO.println "PASS: passed is terminal"

  if !LoopState.isTerminal (.stuck 3 ["test"]) then
    IO.eprintln "FAIL: stuck should be terminal"
    failed := failed + 1
  else
    IO.println "PASS: stuck is terminal"

  if LoopState.isTerminal (.ready) then
    IO.eprintln "FAIL: ready should not be terminal"
    failed := failed + 1
  else
    IO.println "PASS: ready is not terminal"

  if LoopState.isTerminal (.workerRunning 1) then
    IO.eprintln "FAIL: workerRunning should not be terminal"
    failed := failed + 1
  else
    IO.println "PASS: workerRunning is not terminal"

  -- Test: VerificationResult helpers
  if !VerificationResult.isPassed (.pass "ok") then
    IO.eprintln "FAIL: pass should isPassed"
    failed := failed + 1
  else
    IO.println "PASS: VerificationResult.isPassed"

  if !VerificationResult.isFailed (.fail "error") then
    IO.eprintln "FAIL: fail should isFailed"
    failed := failed + 1
  else
    IO.println "PASS: VerificationResult.isFailed"

  -- Summary
  IO.println ""
  if failed > 0 then
    IO.eprintln s!"{failed} test(s) failed"
    return 1
  else
    IO.println "All tests passed"
    return 0
