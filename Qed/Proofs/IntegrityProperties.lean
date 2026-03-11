import Qed.Types
import Qed.StateMachine

set_option autoImplicit false

namespace Qed.Proofs.IntegrityProperties

open Qed Qed.StateMachine

/-- An integrityViolation event from any non-terminal state produces a
    terminal integrityViolation state. The state machine cannot continue
    executing after integrity is violated. -/
theorem integrity_violation_terminal (config : LoopConfig) (state : LoopState)
    (context : LoopContext) (reason : String)
    (hnonterm : state.isTerminal = false) :
    (transition config state context (.integrityViolation reason)).1 =
      .integrityViolation reason := by
  unfold transition
  simp [hnonterm]

/-- The integrityViolation state is terminal — no event can transition out
    of it. This is a specialization of terminal_absorbing, stated explicitly
    for the spec integrity contract. -/
theorem integrity_violation_absorbing (config : LoopConfig) (context : LoopContext)
    (reason : String) (event : LoopEvent) :
    transition config (.integrityViolation reason) context event =
      (.integrityViolation reason, context) := by
  unfold transition
  simp [LoopState.isTerminal]

/-- Integrity violation from a non-terminal state can never produce a passed
    state. If integrity is violated during execution, results are never accepted. -/
theorem integrity_violation_not_passed (config : LoopConfig) (state : LoopState)
    (context : LoopContext) (reason : String) (n : Nat)
    (hnonterm : state.isTerminal = false) :
    (transition config state context (.integrityViolation reason)).1 ≠ .passed n := by
  unfold transition
  simp [hnonterm]

end Qed.Proofs.IntegrityProperties
