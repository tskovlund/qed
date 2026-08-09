import Qed.WorkerLoop

set_option autoImplicit false

namespace Qed.Proofs.WorkerLoopProperties

open Qed

/-- The worker loop's step function is exactly StateMachine.transition.
    This proves the loop drives the proven state machine exclusively. -/
theorem step_eq_transition (config : LoopConfig) (state : LoopState)
    (context : StateMachine.LoopContext) (event : StateMachine.LoopEvent) :
    WorkerLoop.step config state context event =
    StateMachine.transition config state context event := by
  rfl

/-- When there are no failures, buildPrompt returns the base prompt unchanged. -/
theorem buildPrompt_empty_failures (base : String) (n : Nat) :
    WorkerLoop.buildPrompt base [] n = base := by
  simp [WorkerLoop.buildPrompt, List.isEmpty]

/-- When there are failures, buildPrompt extends the base prompt —
    the result is base ++ suffix for some suffix. -/
theorem buildPrompt_nonempty_appends (base : String)
    (desc : String) (result : VerificationResult)
    (rest : List (String × VerificationResult)) (n : Nat) :
    ∃ suffix, WorkerLoop.buildPrompt base ((desc, result) :: rest) n = base ++ suffix := by
  unfold WorkerLoop.buildPrompt
  simp only [List.isEmpty_cons]
  rw [String.append_assoc]
  exact ⟨_, rfl⟩

/-- shellQuote wraps its input in single quotes. -/
theorem shellQuote_wraps (s : String) :
    ∃ inner, WorkerLoop.shellQuote s = "'" ++ inner ++ "'" := by
  exact ⟨s.replace "'" "'\\''", rfl⟩

/-- shellQuote of the empty string produces "''".

    Closed by `native_decide`, not the kernel: `String.Slice.replace` is defined
    by well-founded recursion and has no upstream reduction lemma, so `rfl`,
    `decide`, and `simp [String.replace]` all fail here. This is the repo's only
    proof that leans on the compiler rather than the kernel — see the note in
    `docs/proven-properties.md`. -/
theorem shellQuote_empty :
    WorkerLoop.shellQuote "" = "''" := by
  native_decide

end Qed.Proofs.WorkerLoopProperties
