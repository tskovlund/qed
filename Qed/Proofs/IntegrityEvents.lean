import Qed.Types
import Qed.StateMachine

set_option autoImplicit false

namespace Qed.Proofs.IntegrityEvents

open Qed Qed.StateMachine

/-! # State machine response to the `integrityViolation` event -/

/-- A violation from any live state lands in `integrityViolation`, so the loop
    stops the moment integrity is lost. -/
theorem integrity_violation_terminal (config : LoopConfig) (state : LoopState)
    (context : LoopContext) (reason : String)
    (hnonterm : state.isTerminal = false) :
    (transition config state context (.integrityViolation reason)).1 =
      .integrityViolation reason := by
  unfold transition
  simp [hnonterm]

/-- No event transitions out of `integrityViolation`. -/
theorem integrity_violation_absorbing (config : LoopConfig) (context : LoopContext)
    (reason : String) (event : LoopEvent) :
    transition config (.integrityViolation reason) context event =
      (.integrityViolation reason, context) := by
  unfold transition
  simp [LoopState.isTerminal]

/-- A violation can never yield `passed`: results are never accepted once
    integrity is lost. -/
theorem integrity_violation_not_passed (config : LoopConfig) (state : LoopState)
    (context : LoopContext) (reason : String) (n : Nat)
    (hnonterm : state.isTerminal = false) :
    (transition config state context (.integrityViolation reason)).1 ≠ .passed n := by
  unfold transition
  simp [hnonterm]

end Qed.Proofs.IntegrityEvents
