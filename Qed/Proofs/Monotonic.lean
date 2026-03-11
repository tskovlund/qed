import Qed.Types
import Qed.StateMachine

set_option autoImplicit false

namespace Qed.Proofs.Monotonic

open Qed Qed.StateMachine

/-- Extract the iteration count from a LoopState. Non-iteration states
(ready, escalated) are assigned 0. -/
def iterationOf : LoopState → Nat
  | .ready => 0
  | .workerRunning n => n
  | .verifying n => n
  | .passed n => n
  | .stuck n _ => n
  | .maxIterationsReached n => n
  | .escalated _ => 0
  | .integrityViolation _ => 0

/-- The iteration count embedded in the state never decreases across a
non-terminal transition, or the result is terminal. Terminal states
(like integrityViolation) may have iterationOf = 0, which correctly
breaks monotonicity — the iteration count is irrelevant for terminal states. -/
theorem iteration_monotonic (config : LoopConfig) (state : LoopState)
    (context : LoopContext) (event : LoopEvent) :
    iterationOf (transition config state context event).1 ≥ iterationOf state
    ∨ (transition config state context event).1.isTerminal = true := by
  unfold transition newFailureCount
  cases h : state.isTerminal
  case false =>
    simp only [Bool.false_eq_true, ↓reduceIte]
    cases state with
    | ready => cases event <;> simp [iterationOf, LoopState.isTerminal]
    | workerRunning n =>
      cases event with
      | workerDone => left; simp [iterationOf]
      | allPassed => left; simp [iterationOf]
      | someFailed _ => left; simp [iterationOf]
      | integrityViolation _ => right; simp [LoopState.isTerminal]
    | verifying n =>
      cases event with
      | allPassed => right; simp [LoopState.isTerminal]
      | workerDone => left; simp [iterationOf]
      | someFailed failures =>
        simp only []
        split
        · right; simp [LoopState.isTerminal]
        · split <;> split
          · right; simp [LoopState.isTerminal]
          · left; simp [iterationOf]
          · right; simp [LoopState.isTerminal]
          · left; simp [iterationOf]
      | integrityViolation _ => right; simp [LoopState.isTerminal]
    | passed _ => simp [LoopState.isTerminal] at h
    | stuck _ _ => simp [LoopState.isTerminal] at h
    | maxIterationsReached _ => simp [LoopState.isTerminal] at h
    | escalated _ => simp [LoopState.isTerminal] at h
    | integrityViolation _ => simp [LoopState.isTerminal] at h
  case true =>
    simp only [↓reduceIte]
    left; exact Nat.le_refl _

end Qed.Proofs.Monotonic
