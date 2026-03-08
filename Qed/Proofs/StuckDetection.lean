import Qed.Types
import Qed.StateMachine

set_option autoImplicit false

namespace Qed.Proofs.StuckDetection

open Qed Qed.StateMachine

/-- Stuck detection fires when `consecutiveFailureCount` reaches `stuckThreshold`.
When transitioning from `verifying` with `someFailed` and the iteration has
not reached `maxIterations`, if the computed new count reaches `stuckThreshold`,
the result state is `.stuck`. -/
theorem stuck_when_threshold_reached (config : LoopConfig) (iteration : Nat)
    (context : LoopContext) (failures : List String)
    (hiter : ¬ iteration ≥ config.maxIterations)
    (hstuck : newFailureCount context failures ≥ config.stuckThreshold) :
    (transition config (.verifying iteration) context (.someFailed failures)).1 =
      .stuck iteration failures := by
  unfold transition newFailureCount at *
  simp only [LoopState.isTerminal, Bool.false_eq_true, ↓reduceIte] at *
  split at hstuck <;> split <;> simp_all <;> omega

/-- Conversely, when the computed count has not reached `stuckThreshold`,
the transition produces `workerRunning` (retry), not `stuck`. -/
theorem not_stuck_when_below_threshold (config : LoopConfig) (iteration : Nat)
    (context : LoopContext) (failures : List String)
    (hiter : ¬ iteration ≥ config.maxIterations)
    (hnostuck : ¬ newFailureCount context failures ≥ config.stuckThreshold) :
    (transition config (.verifying iteration) context (.someFailed failures)).1 =
      .workerRunning (iteration + 1) := by
  unfold transition newFailureCount at *
  simp only [LoopState.isTerminal, Bool.false_eq_true, ↓reduceIte] at *
  split at hnostuck <;> split <;> simp_all <;> omega

/-- When transitioning from `verifying` with `someFailed` and the iteration has
not reached `maxIterations`, the new `consecutiveFailureCount` is incremented
if failures match the previous ones and reset to 1 otherwise. -/
theorem failure_count_update (config : LoopConfig) (iteration : Nat)
    (context : LoopContext) (failures : List String)
    (hiter : ¬ iteration ≥ config.maxIterations)
    (hnostuck : ¬ newFailureCount context failures ≥ config.stuckThreshold) :
    (transition config (.verifying iteration) context (.someFailed failures)).2.consecutiveFailureCount =
      newFailureCount context failures := by
  unfold transition newFailureCount at *
  simp only [LoopState.isTerminal, Bool.false_eq_true, ↓reduceIte] at *
  split at hnostuck <;> split <;> simp_all <;> omega

/-- Stuck detection is an iff: the transition from `verifying` with `someFailed`
(below maxIterations) produces `.stuck` if and only if the computed consecutive
failure count reaches the stuck threshold. -/
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
    exact stuck_when_threshold_reached config iteration context failures hiter h

end Qed.Proofs.StuckDetection
