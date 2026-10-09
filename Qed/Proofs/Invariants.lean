import Qed.Types
import Qed.StateMachine
import Qed.Proofs.Monotonic

set_option autoImplicit false

namespace Qed.Proofs.Invariants

open Qed Qed.StateMachine

/-- The lifecycle phase of a state: initial (0), working (1), terminal (2).
Working states (workerRunning, verifying) cycle at the same phase during
retries, but the phase never decreases. -/
def statePhase : LoopState → Nat
  | .ready => 0
  | .workerRunning _ => 1
  | .verifying _ => 1
  | .passed _ => 2
  | .stuck _ _ => 2
  | .maxIterationsReached _ => 2
  | .escalated _ => 2
  | .integrityViolation _ => 2

/-- The initial state `ready` is never revisited: no non-terminal transition
produces `ready`. Combined with terminal absorption, this means `ready` is
visited exactly once at the start of the loop. -/
theorem ready_unreachable (config : LoopConfig) (state : LoopState)
    (context : LoopContext) (event : LoopEvent)
    (hnonterm : state.isTerminal = false) :
    (transition config state context event).1 ≠ .ready := by
  unfold transition newFailureCount
  simp only [hnonterm, Bool.false_eq_true, ↓reduceIte]
  cases state with
  | ready => cases event <;> simp
  | workerRunning n => cases event <;> simp
  | verifying n =>
    cases event with
    | allPassed => simp
    | workerDone => simp
    | someFailed failures =>
      simp only []
      split
      · simp
      · split <;> split <;> simp
    | integrityViolation _ => simp
  | passed _ => simp [LoopState.isTerminal] at hnonterm
  | stuck _ _ => simp [LoopState.isTerminal] at hnonterm
  | maxIterationsReached _ => simp [LoopState.isTerminal] at hnonterm
  | escalated _ => simp [LoopState.isTerminal] at hnonterm
  | integrityViolation _ => simp [LoopState.isTerminal] at hnonterm

/-- States only move forward through lifecycle phases: initial → working →
terminal. The working phase (workerRunning ↔ verifying) allows cycling
during retries, but no transition moves to an earlier phase. -/
theorem phase_monotonic (config : LoopConfig) (state : LoopState)
    (context : LoopContext) (event : LoopEvent) :
    statePhase (transition config state context event).1 ≥ statePhase state := by
  unfold transition newFailureCount
  cases h : state.isTerminal
  case false =>
    simp only [Bool.false_eq_true, ↓reduceIte]
    cases state with
    | ready => cases event <;> simp [statePhase]
    | workerRunning n => cases event <;> simp [statePhase]
    | verifying n =>
      cases event with
      | allPassed => simp [statePhase]
      | workerDone => simp [statePhase]
      | someFailed failures =>
        simp only []
        split
        · simp [statePhase]
        · split <;> split <;> simp [statePhase]
      | integrityViolation _ => simp [statePhase]
    | passed _ => simp [LoopState.isTerminal] at h
    | stuck _ _ => simp [LoopState.isTerminal] at h
    | maxIterationsReached _ => simp [LoopState.isTerminal] at h
    | escalated _ => simp [LoopState.isTerminal] at h
    | integrityViolation _ => simp [LoopState.isTerminal] at h
  case true =>
    simp only [↓reduceIte]
    exact Nat.le_refl _

/-- The iteration count in any state produced by a transition never exceeds
`maxIterations`, provided the input state also satisfies the bound and
`maxIterations ≥ 1`. This guarantees the system never runs more iterations
than configured. -/
theorem iteration_bounded (config : LoopConfig) (state : LoopState)
    (context : LoopContext) (event : LoopEvent)
    (hconfig : config.maxIterations ≥ 1)
    (hbound : Monotonic.iterationOf state ≤ config.maxIterations) :
    Monotonic.iterationOf (transition config state context event).1
      ≤ config.maxIterations := by
  unfold transition newFailureCount
  cases h : state.isTerminal
  case false =>
    simp only [Bool.false_eq_true, ↓reduceIte]
    cases state with
    | ready =>
      cases event <;> simp [Monotonic.iterationOf] <;> exact hconfig
    | workerRunning n =>
      cases event <;> simp [Monotonic.iterationOf] <;> exact hbound
    | verifying n =>
      cases event with
      | allPassed => simp [Monotonic.iterationOf]; exact hbound
      | workerDone => simp [Monotonic.iterationOf]; exact hbound
      | someFailed failures =>
        simp only []
        split
        · simp [Monotonic.iterationOf]; exact hbound
        · rename_i hlt
          split <;> split <;> simp [Monotonic.iterationOf]
          all_goals omega
      | integrityViolation _ => simp [Monotonic.iterationOf]
    | passed _ => simp [LoopState.isTerminal] at h
    | stuck _ _ => simp [LoopState.isTerminal] at h
    | maxIterationsReached _ => simp [LoopState.isTerminal] at h
    | escalated _ => simp [LoopState.isTerminal] at h
    | integrityViolation _ => simp [LoopState.isTerminal] at h
  case true =>
    simp only [↓reduceIte]
    exact hbound

/-- The initial state `ready` always advances: it transitions to
`workerRunning 1` on any non-integrity event, or to `integrityViolation`
on an integrity violation. This fully characterizes ready transitions. -/
theorem ready_always_advances (config : LoopConfig) (context : LoopContext)
    (event : LoopEvent) :
    (transition config .ready context event).1 = .workerRunning 1 ∨
    (∃ reason, (transition config .ready context event).1 = .integrityViolation reason) := by
  unfold transition
  simp [LoopState.isTerminal]
  cases event with
  | workerDone => left; rfl
  | allPassed => left; rfl
  | someFailed _ => left; rfl
  | integrityViolation reason => right; exact ⟨reason, rfl⟩

/-- Every non-terminal transition either terminates, self-loops, or follows one
of exactly three advance patterns. This is a complete characterization of
the lifecycle: ready → workerRunning → verifying → (terminal ∨ next iteration).

Composes and subsumes no_skip_verification, worker_before_verification,
ready_unreachable, and phase_monotonic into a single theorem. -/
theorem lifecycle_ordering (config : LoopConfig) (state : LoopState)
    (context : LoopContext) (event : LoopEvent)
    (hnonterm : state.isTerminal = false) :
    let result := (transition config state context event).1
    -- Either terminal
    result.isTerminal = true ∨
    -- Or stays in same state (self-loop)
    result = state ∨
    -- Or advances: ready → workerRunning(1)
    (state = .ready ∧ result = .workerRunning 1) ∨
    -- Or advances: workerRunning → verifying (same iteration)
    (∃ n, state = .workerRunning n ∧ result = .verifying n) ∨
    -- Or advances: verifying → workerRunning (next iteration)
    (∃ n, state = .verifying n ∧ result = .workerRunning (n + 1)) := by
  unfold transition newFailureCount
  simp only [hnonterm, Bool.false_eq_true, ↓reduceIte]
  cases state with
  | ready =>
    cases event with
    | workerDone => right; right; left; exact ⟨rfl, rfl⟩
    | allPassed => right; right; left; exact ⟨rfl, rfl⟩
    | someFailed _ => right; right; left; exact ⟨rfl, rfl⟩
    | integrityViolation _ => left; simp [LoopState.isTerminal]
  | workerRunning n =>
    cases event with
    | workerDone => right; right; right; left; exact ⟨n, rfl, rfl⟩
    | allPassed => right; left; rfl
    | someFailed _ => right; left; rfl
    | integrityViolation _ => left; simp [LoopState.isTerminal]
  | verifying n =>
    cases event with
    | allPassed => left; simp [LoopState.isTerminal]
    | workerDone => right; left; rfl
    | someFailed failures =>
      simp only []
      split
      · left; simp [LoopState.isTerminal]
      · split
        · split
          · left; simp [LoopState.isTerminal]
          · right; right; right; right; exact ⟨n, rfl, rfl⟩
        · split
          · left; simp [LoopState.isTerminal]
          · right; right; right; right; exact ⟨n, rfl, rfl⟩
    | integrityViolation _ => left; simp [LoopState.isTerminal]
  | passed _ => simp [LoopState.isTerminal] at hnonterm
  | stuck _ _ => simp [LoopState.isTerminal] at hnonterm
  | maxIterationsReached _ => simp [LoopState.isTerminal] at hnonterm
  | escalated _ => simp [LoopState.isTerminal] at hnonterm
  | integrityViolation _ => simp [LoopState.isTerminal] at hnonterm

end Qed.Proofs.Invariants
