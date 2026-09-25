import Qed.WorkerLoop

set_option autoImplicit false

namespace Qed.Proofs.WorkerLoopProperties

open Qed

/-! # Worker loop properties -/

/-- The loop drives the proven state machine and nothing else. -/
theorem step_eq_transition (config : LoopConfig) (state : LoopState)
    (context : StateMachine.LoopContext) (event : StateMachine.LoopEvent) :
    WorkerLoop.step config state context event =
    StateMachine.transition config state context event := by
  rfl

theorem buildPrompt_empty_failures (base : String) (n : Nat) :
    WorkerLoop.buildPrompt base [] n = base := by
  simp [WorkerLoop.buildPrompt, List.isEmpty]

/-- Failure feedback extends the operator's prompt; it never replaces or
    reorders it. -/
theorem buildPrompt_nonempty_appends (base : String)
    (desc : String) (result : VerificationResult)
    (rest : List (String × VerificationResult)) (n : Nat) :
    ∃ suffix, WorkerLoop.buildPrompt base ((desc, result) :: rest) n = base ++ suffix := by
  unfold WorkerLoop.buildPrompt
  simp only [List.isEmpty_cons]
  rw [String.append_assoc]
  exact ⟨_, rfl⟩

end Qed.Proofs.WorkerLoopProperties
