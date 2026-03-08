import Qed.Types
import Qed.StateMachine

set_option autoImplicit false

namespace Qed.Proofs.FinalStates

open Qed Qed.StateMachine

/-- Terminal states are absorbing: transitioning from a terminal state always
returns the same state and context unchanged. This follows directly from the
`isTerminal` guard at the top of the transition function. -/
theorem terminal_absorbing (config : LoopConfig) (state : LoopState)
    (context : LoopContext) (event : LoopEvent)
    (h : state.isTerminal = true) :
    transition config state context event = (state, context) := by
  unfold transition
  simp [h]

end Qed.Proofs.FinalStates
