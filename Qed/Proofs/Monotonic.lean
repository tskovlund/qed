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

/-- The iteration count embedded in the state never decreases across a
transition. If the current state has iteration n, the next state has
iteration >= n. -/
theorem iteration_monotonic (config : LoopConfig) (state : LoopState)
    (context : LoopContext) (event : LoopEvent) :
    iterationOf (transition config state context event).1 ≥ iterationOf state := by
  unfold transition newFailureCount
  cases h : state.isTerminal
  case false =>
    simp only [Bool.false_eq_true, ↓reduceIte]
    cases state with
    | ready => cases event <;> simp [iterationOf]
    | workerRunning n => cases event <;> simp [iterationOf]
    | verifying n =>
      cases event with
      | allPassed => simp [iterationOf]
      | workerDone => simp [iterationOf]
      | someFailed failures =>
        simp only []
        split
        · simp [iterationOf]
        · split <;> split <;> simp [iterationOf]
    | passed _ => simp [LoopState.isTerminal] at h
    | stuck _ _ => simp [LoopState.isTerminal] at h
    | maxIterationsReached _ => simp [LoopState.isTerminal] at h
    | escalated _ => simp [LoopState.isTerminal] at h
  case true =>
    simp only [↓reduceIte]
    exact Nat.le_refl _

end Qed.Proofs.Monotonic
