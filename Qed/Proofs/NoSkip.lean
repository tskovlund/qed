import Qed.Types
import Qed.StateMachine

set_option autoImplicit false

namespace Qed.Proofs.NoSkip

open Qed Qed.StateMachine

/-- Cannot reach `passed` without going through `verifying` first.
If a non-terminal state transitions to `passed`, the previous state must have
been `verifying`. This follows from exhaustive case analysis on the transition
function: the only branch producing `.passed` from a non-terminal state is
`(.verifying n, .allPassed)`. -/
theorem no_skip_verification (config : LoopConfig) (state : LoopState)
    (context : LoopContext) (event : LoopEvent) (n : Nat)
    (hnonterm : state.isTerminal = false)
    (h : (transition config state context event).1 = .passed n) :
    ∃ (m : Nat), state = .verifying m := by
  unfold transition newFailureCount at h
  simp only [hnonterm, Bool.false_eq_true, ↓reduceIte] at h
  cases state with
  | ready => cases event <;> simp at h
  | workerRunning k => cases event <;> simp at h
  | verifying k => exact ⟨k, rfl⟩
  | passed _ => simp [LoopState.isTerminal] at hnonterm
  | stuck _ _ => simp [LoopState.isTerminal] at hnonterm
  | maxIterationsReached _ => simp [LoopState.isTerminal] at hnonterm
  | escalated _ => simp [LoopState.isTerminal] at hnonterm

/-- `verifying(n)` is only reachable from `workerRunning(n)` via a single
non-terminal transition. If a non-terminal state transitions to `.verifying m`,
then either:
- the previous state was `.workerRunning m` (normal progression via workerDone), or
- the previous state was `.verifying m` (self-loop on spurious workerDone). -/
theorem worker_before_verification (config : LoopConfig) (state : LoopState)
    (context : LoopContext) (event : LoopEvent) (m : Nat)
    (hnonterm : state.isTerminal = false)
    (h : (transition config state context event).1 = .verifying m) :
    state = .workerRunning m ∨ state = .verifying m := by
  unfold transition newFailureCount at h
  simp only [hnonterm, Bool.false_eq_true, ↓reduceIte] at h
  cases state with
  | ready => cases event <;> simp at h
  | workerRunning k =>
    cases event with
    | workerDone =>
      simp at h; left; congr
    | allPassed => simp at h
    | someFailed _ => simp at h
  | verifying k =>
    cases event with
    | allPassed => simp at h
    | someFailed failures =>
      exfalso
      simp at h
      split at h
      · simp at h
      · split at h <;> (split at h <;> simp at h)
    | workerDone =>
      simp at h; right; congr
  | passed _ => simp [LoopState.isTerminal] at hnonterm
  | stuck _ _ => simp [LoopState.isTerminal] at hnonterm
  | maxIterationsReached _ => simp [LoopState.isTerminal] at hnonterm
  | escalated _ => simp [LoopState.isTerminal] at hnonterm

end Qed.Proofs.NoSkip
