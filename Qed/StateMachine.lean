import Qed.Types

namespace Qed.StateMachine

open Qed

/-- Events that drive state transitions. -/
inductive LoopEvent where
  /-- Worker has completed its run. -/
  | workerDone
  /-- All auto-verifiable criteria passed. -/
  | allPassed
  /-- Some criteria failed. Carries the list of failing criterion descriptions. -/
  | someFailed (failingCriteria : List String)
  deriving Repr, BEq

/-- Internal state tracking consecutive identical failures for stuck detection. -/
structure LoopContext where
  /-- How many consecutive iterations had the exact same failures. -/
  consecutiveFailureCount : Nat
  /-- The failing criteria from the previous iteration (for comparison). -/
  previousFailures : List String
  deriving Repr, BEq

/-- Initial loop context. -/
def LoopContext.initial : LoopContext :=
  { consecutiveFailureCount := 0, previousFailures := [] }

/-- Compute the new consecutive failure count given the current context and
the latest failures. Increments if failures match the previous iteration,
resets to 1 otherwise. Used by both `transition` and proofs. -/
def newFailureCount (context : LoopContext) (failures : List String) : Nat :=
  if failures == context.previousFailures then context.consecutiveFailureCount + 1 else 1

/-- The pure transition function. No IO, no side effects.

Given the current state, context, config, and an event, produces the next
state and updated context. All proofs reason about this function. -/
def transition (config : LoopConfig) (state : LoopState) (context : LoopContext)
    (event : LoopEvent) : LoopState × LoopContext :=
  -- Terminal states are absorbing — ignore all events
  if state.isTerminal then
    (state, context)
  else
    match state, event with
    -- ready → workerRunning(1) on any event (start the loop)
    | .ready, _ =>
      (.workerRunning 1, context)

    -- workerRunning → verifying when worker completes
    | .workerRunning iteration, .workerDone =>
      (.verifying iteration, context)
    -- workerRunning: ignore other events (worker still running)
    | .workerRunning iteration, _ =>
      (.workerRunning iteration, context)

    -- verifying + allPassed → passed
    | .verifying iteration, .allPassed =>
      (.passed iteration, context)

    -- verifying + someFailed → check stuck, max iterations, or retry
    | .verifying iteration, .someFailed failures =>
      -- Check max iterations first
      if iteration ≥ config.maxIterations then
        (.maxIterationsReached iteration, context)
      else
        -- Check stuck detection: same failures for stuckThreshold consecutive iterations
        let newCount := newFailureCount context failures
        let newContext := { consecutiveFailureCount := newCount, previousFailures := failures }
        if newCount ≥ config.stuckThreshold then
          (.stuck iteration failures, newContext)
        else
          -- Retry: go back to workerRunning with incremented iteration
          (.workerRunning (iteration + 1), newContext)

    -- verifying: workerDone doesn't make sense during verification
    | .verifying iteration, .workerDone =>
      (.verifying iteration, context)

    -- Terminal states handled by isTerminal guard above, but Lean needs exhaustiveness.
    -- These are unreachable due to the isTerminal check.
    | .passed iterations, _ => (.passed iterations, context)
    | .stuck iterations failingCriteria, _ => (.stuck iterations failingCriteria, context)
    | .maxIterationsReached iterations, _ => (.maxIterationsReached iterations, context)
    | .escalated reason, _ => (.escalated reason, context)

end Qed.StateMachine
