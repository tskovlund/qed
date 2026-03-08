import Qed.Types
import Qed.StateMachine
import Qed.Proofs.Monotonic

set_option autoImplicit false

namespace Qed.Proofs.Termination

open Qed Qed.StateMachine

/-- Every transition from `verifying` with `someFailed` produces one of exactly
three outcomes: maxIterationsReached, stuck, or workerRunning (iteration + 1).
The first two are terminal. This is the key lemma for termination. -/
theorem verify_someFailed_outcomes (config : LoopConfig)
    (iteration : Nat) (context : LoopContext) (failures : List String) :
    let result := (transition config (.verifying iteration) context (.someFailed failures)).1
    (∃ n, result = .maxIterationsReached n) ∨
    (∃ n fs, result = .stuck n fs) ∨
    result = .workerRunning (iteration + 1) := by
  unfold transition
  simp [LoopState.isTerminal]
  -- Three levels of if: maxIterations, failures==prev, stuckThreshold
  split
  · left; exact ⟨iteration, rfl⟩
  · split <;> split
    · right; left; exact ⟨iteration, failures, rfl⟩
    · right; right; rfl
    · right; left; exact ⟨iteration, failures, rfl⟩
    · right; right; rfl

/-- Every non-terminal transition from `verifying` with `someFailed` either:
1. Produces a terminal state (maxIterationsReached or stuck), or
2. Produces `workerRunning (iteration + 1)` (strictly incrementing iteration).

Combined with the maxIterations bound, the loop must terminate. -/
theorem verify_someFailed_terminates_or_increments (config : LoopConfig)
    (iteration : Nat) (context : LoopContext) (failures : List String) :
    let result := transition config (.verifying iteration) context (.someFailed failures)
    result.1.isTerminal = true ∨ result.1 = .workerRunning (iteration + 1) := by
  have h := verify_someFailed_outcomes config iteration context failures
  cases h with
  | inl h =>
    left; obtain ⟨n, hn⟩ := h; simp [hn, LoopState.isTerminal]
  | inr h =>
    cases h with
    | inl h =>
      left; obtain ⟨n, fs, hn⟩ := h; simp [hn, LoopState.isTerminal]
    | inr h =>
      right; exact h

/-- Every non-terminal transition from `verifying` with `allPassed` produces
a terminal state (`passed`). -/
theorem verify_allPassed_terminates (config : LoopConfig) (iteration : Nat)
    (context : LoopContext) :
    (transition config (.verifying iteration) context .allPassed).1.isTerminal = true := by
  unfold transition
  simp [LoopState.isTerminal]

/-- Every non-terminal transition from `verifying` with `workerDone` stays in
`verifying` (same iteration). -/
theorem verify_workerDone_stays (config : LoopConfig) (iteration : Nat)
    (context : LoopContext) :
    (transition config (.verifying iteration) context .workerDone).1 = .verifying iteration := by
  unfold transition
  simp [LoopState.isTerminal]

/-- A non-terminal transition from `workerRunning` either stays in
`workerRunning` (on non-workerDone events) or advances to `verifying`. -/
theorem workerRunning_transition (config : LoopConfig) (iteration : Nat)
    (context : LoopContext) (event : LoopEvent) :
    let result := transition config (.workerRunning iteration) context event
    result.1 = .workerRunning iteration ∨ result.1 = .verifying iteration := by
  unfold transition
  simp [LoopState.isTerminal]
  cases event with
  | workerDone => right; rfl
  | allPassed => left; rfl
  | someFailed _ => left; rfl

/-- Terminal states are absorbing. -/
theorem terminal_absorbing (config : LoopConfig) (state : LoopState)
    (context : LoopContext) (event : LoopEvent)
    (h : state.isTerminal = true) :
    transition config state context event = (state, context) := by
  unfold transition
  simp [h]

/-- The fuel measure: maxIterations - current iteration. For any non-terminal
transition from `verifying` with `someFailed` that doesn't terminate, the fuel
strictly decreases. Since fuel is a natural number, the loop must terminate. -/
theorem fuel_decreases_on_retry (config : LoopConfig) (iteration : Nat)
    (context : LoopContext) (failures : List String)
    (hiter : ¬ iteration ≥ config.maxIterations)
    (result_state : LoopState)
    (hresult : (transition config (.verifying iteration) context (.someFailed failures)).1 = result_state)
    (hnotterm : result_state.isTerminal = false) :
    config.maxIterations - Monotonic.iterationOf result_state <
      config.maxIterations - iteration := by
  have key := verify_someFailed_terminates_or_increments config iteration context failures
  cases key with
  | inl hterm =>
    rw [← hresult] at hnotterm
    simp [hterm] at hnotterm
  | inr hworker =>
    rw [hworker] at hresult
    rw [← hresult]
    simp [Monotonic.iterationOf]
    omega

/-- The loop terminates: each non-terminal transition from `verifying` with
`someFailed` either terminates immediately or produces `workerRunning` with a
strictly higher iteration. Since iteration is bounded by maxIterations and is
a natural number, this can only happen finitely many times. -/
theorem loop_terminates (config : LoopConfig) (iteration : Nat)
    (ctx : LoopContext) (failures : List String)
    (hiter : iteration < config.maxIterations) :
    (transition config (.verifying iteration) ctx (.someFailed failures)).1.isTerminal = true ∨
    ∃ (n : Nat), n = iteration + 1 ∧ n ≤ config.maxIterations ∧
      (transition config (.verifying iteration) ctx (.someFailed failures)).1 = .workerRunning n := by
  have key := verify_someFailed_terminates_or_increments config iteration ctx failures
  cases key with
  | inl hterm => left; exact hterm
  | inr hworker =>
    right
    exact ⟨iteration + 1, rfl, by omega, hworker⟩

end Qed.Proofs.Termination
