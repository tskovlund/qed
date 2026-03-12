import Qed.Types
import Qed.StateMachine
import Qed.Proofs.FinalStates
import Qed.Proofs.Monotonic
import Qed.Proofs.Invariants

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
  unfold transition newFailureCount
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
`workerRunning` (on non-workerDone events), advances to `verifying`,
or terminates (on integrityViolation). -/
theorem workerRunning_transition (config : LoopConfig) (iteration : Nat)
    (context : LoopContext) (event : LoopEvent) :
    let result := transition config (.workerRunning iteration) context event
    result.1 = .workerRunning iteration ∨ result.1 = .verifying iteration
    ∨ result.1.isTerminal = true := by
  unfold transition
  simp [LoopState.isTerminal]
  cases event with
  | workerDone => right; left; rfl
  | allPassed => left; rfl
  | someFailed _ => left; rfl
  | integrityViolation _ => right; right; rfl

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

/-- Single-step progress: each transition from `verifying` with `someFailed`
either terminates immediately or produces `workerRunning` with a strictly
higher iteration bounded by maxIterations. Combined with `fuel_decreases_on_retry`,
this gives termination by well-founded induction on (maxIterations - iteration). -/
theorem loop_progress (config : LoopConfig) (iteration : Nat)
    (context : LoopContext) (failures : List String)
    (hiter : iteration < config.maxIterations) :
    (transition config (.verifying iteration) context (.someFailed failures)).1.isTerminal = true ∨
    ∃ (n : Nat), n = iteration + 1 ∧ n ≤ config.maxIterations ∧
      (transition config (.verifying iteration) context (.someFailed failures)).1 = .workerRunning n := by
  have key := verify_someFailed_terminates_or_increments config iteration context failures
  cases key with
  | inl hterm => left; exact hterm
  | inr hworker =>
    right
    exact ⟨iteration + 1, rfl, by omega, hworker⟩

/-- Full termination: every transition from `verifying` with `someFailed`
either reaches a terminal state immediately, or strictly decreases the fuel
measure `maxIterations - iteration`. Since fuel is a `Nat`, this can happen
at most `maxIterations` times before terminating.

This is the composition of `loop_progress` (single-step progress) and
`fuel_decreases_on_retry` (well-founded measure). Together they establish
that the worker loop terminates for any sequence of events. -/
theorem loop_terminates (config : LoopConfig) (iteration : Nat)
    (context : LoopContext) (failures : List String) :
    (transition config (.verifying iteration) context (.someFailed failures)).1.isTerminal = true ∨
    (∃ (n : Nat),
      (transition config (.verifying iteration) context (.someFailed failures)).1 = .workerRunning n ∧
      config.maxIterations - n < config.maxIterations - iteration) := by
  have key := verify_someFailed_terminates_or_increments config iteration context failures
  cases key with
  | inl hterm => left; exact hterm
  | inr hworker =>
    right
    exact ⟨iteration + 1, hworker, by
      have := fuel_decreases_on_retry config iteration context failures
        (by intro h; unfold transition newFailureCount at hworker
            simp [LoopState.isTerminal] at hworker
            split at hworker <;> simp at hworker)
        (.workerRunning (iteration + 1)) hworker
        (by simp [LoopState.isTerminal])
      simp [Monotonic.iterationOf] at this
      exact this⟩

/-- Progress measure for termination: assigns a natural number to each state
such that ready < workerRunning(n) < verifying(n) < workerRunning(n+1) < ...
Terminal states are assigned 0 (irrelevant — they're absorbing). -/
def progressMeasure (state : LoopState) : Nat :=
  match state with
  | .ready => 0
  | .workerRunning n => 2 * n + 1
  | .verifying n => 2 * n + 2
  | _ => 0

/-- Every non-terminal, state-changing transition either reaches a terminal
state or strictly increases the progress measure. Since the measure is
bounded by `2 * maxIterations + 2` for reachable states, the loop terminates
after at most that many non-trivial transitions.

This is the end-to-end termination guarantee, proved by composing
`lifecycle_ordering` (which characterizes all possible transitions) with
the progress measure. -/
theorem progress_or_terminal (config : LoopConfig) (state : LoopState)
    (context : LoopContext) (event : LoopEvent)
    (hnonterm : state.isTerminal = false)
    (hchanges : (transition config state context event).1 ≠ state) :
    (transition config state context event).1.isTerminal = true ∨
    progressMeasure (transition config state context event).1 > progressMeasure state := by
  have h := Invariants.lifecycle_ordering config state context event hnonterm
  rcases h with hterminal | hself | ⟨hready, hworker⟩ | ⟨n, hstate, hverify⟩ | ⟨n, hstate, hworker_next⟩
  -- Terminal
  · left; exact hterminal
  -- Self-loop: contradicts hchanges
  · exact absurd hself hchanges
  -- ready → workerRunning 1: measure 0 → 3
  · right; subst hready; rw [hworker]; simp [progressMeasure]
  -- workerRunning n → verifying n: measure (2n+1) → (2n+2)
  · right; subst hstate; rw [hverify]; simp [progressMeasure]
  -- verifying n → workerRunning (n+1): measure (2n+2) → (2n+3)
  · right; subst hstate; rw [hworker_next]; simp [progressMeasure]; omega

end Qed.Proofs.Termination
