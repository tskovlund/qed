import Qed.Types
import Qed.StateMachine

set_option autoImplicit false

namespace Qed.Proofs.StuckDetection

open Qed Qed.StateMachine

/-- Complete characterization of stuck detection: the transition from `verifying`
    with `someFailed` (below maxIterations) produces `.stuck` if and only if the
    computed consecutive failure count reaches the stuck threshold. -/
theorem stuck_iff_threshold (config : LoopConfig) (iteration : Nat)
    (context : LoopContext) (failures : List String)
    (hiter : ¬ iteration ≥ config.maxIterations) :
    ((transition config (.verifying iteration) context (.someFailed failures)).1 =
      .stuck iteration failures) ↔ newFailureCount context failures ≥ config.stuckThreshold := by
  constructor
  · -- Forward: if result is stuck, then count >= threshold
    intro h
    unfold transition newFailureCount at *
    simp only [LoopState.isTerminal, Bool.false_eq_true, ↓reduceIte] at *
    split at h
    · simp at h
    · split at h
      · split at h
        · split <;> simp_all <;> omega
        · simp at h
      · split at h
        · split <;> simp_all <;> omega
        · simp at h
  · -- Backward: if count >= threshold, then result is stuck
    intro h
    unfold transition newFailureCount at *
    simp only [LoopState.isTerminal, Bool.false_eq_true, ↓reduceIte] at *
    split at h <;> split <;> simp_all <;> omega

/-- When transitioning from `verifying` with `someFailed` (below maxIterations
    and below stuck threshold), the context's consecutiveFailureCount is updated
    to the new failure count. -/
theorem failure_count_update (config : LoopConfig) (iteration : Nat)
    (context : LoopContext) (failures : List String)
    (hiter : ¬ iteration ≥ config.maxIterations)
    (hnostuck : ¬ newFailureCount context failures ≥ config.stuckThreshold) :
    (transition config (.verifying iteration) context (.someFailed failures)).2.consecutiveFailureCount =
      newFailureCount context failures := by
  unfold transition newFailureCount at *
  simp only [LoopState.isTerminal, Bool.false_eq_true, ↓reduceIte] at *
  split at hnostuck <;> split <;> simp_all <;> omega

end Qed.Proofs.StuckDetection
