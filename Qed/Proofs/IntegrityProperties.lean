import Qed.Types
import Qed.StateMachine

set_option autoImplicit false

namespace Qed.Proofs.IntegrityProperties

open Qed Qed.StateMachine

/-! # Integrity *event* properties — not `Qed/Integrity.lean`

Despite the name, this file proves nothing about `Qed/Integrity.lean`. It does
not import it. Every theorem here is about how `StateMachine.transition`
responds to the `LoopEvent.integrityViolation` event: the violation is
terminal, absorbing, and can never yield `passed`. That is the orchestration
half of the guarantee.

The detection half — `Integrity.hashFile`, `checkGitClean`, and the `verify`
composition that decides *whether* a violation is raised — has no proof
coverage. All six definitions in `Integrity.lean` are `IO`, so there is
nothing pure to attach a theorem to as currently written; behaviour is covered
by tests. Making the composition provable would mean factoring the
"hash check ∧ (pinned → git check)" decision out of `IO` into a pure
combinator.

Read a green build of this file as "the state machine handles violations
correctly", never as "integrity checking is verified". -/

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
