import Qed.Types

set_option autoImplicit false

namespace Qed.Proofs.TypeProperties

open Qed

/-! # Core type characterizations -/

/-- `isTerminal` is true exactly on the five terminal states. -/
theorem isTerminal_iff (state : LoopState) :
    state.isTerminal = true ↔
    (∃ n, state = .passed n) ∨
    (∃ n fs, state = .stuck n fs) ∨
    (∃ n, state = .maxIterationsReached n) ∨
    (∃ n, state = .escalated n) ∨
    (∃ n, state = .integrityViolation n) := by
  cases state <;> simp [LoopState.isTerminal]

/-- Every `VerificationResult` is exactly one of pass, fail, needsHuman, or
    skipped, and the `isPassed`/`isFailed`/`isSkipped` predicates agree with the
    constructor. This is the foundation of the pass/fail decision in
    `OutputCorrectness.allExecutionsPassed_iff_no_failures`. -/
theorem result_complete_partition (result : VerificationResult) :
    (∃ d, result = .pass d) ∧ result.isPassed = true ∧ result.isFailed = false ∧ result.isSkipped = false
  ∨ (∃ d, result = .fail d) ∧ result.isPassed = false ∧ result.isFailed = true ∧ result.isSkipped = false
  ∨ (∃ i, result = .needsHuman i) ∧ result.isPassed = false ∧ result.isFailed = false ∧ result.isSkipped = false
  ∨ (∃ r, result = .skipped r) ∧ result.isPassed = false ∧ result.isFailed = false ∧ result.isSkipped = true := by
  cases result with
  | pass d => exact .inl ⟨⟨d, rfl⟩, rfl, rfl, rfl⟩
  | fail d => exact .inr (.inl ⟨⟨d, rfl⟩, rfl, rfl, rfl⟩)
  | needsHuman i => exact .inr (.inr (.inl ⟨⟨i, rfl⟩, rfl, rfl, rfl⟩))
  | skipped r => exact .inr (.inr (.inr ⟨⟨r, rfl⟩, rfl, rfl, rfl⟩))

end Qed.Proofs.TypeProperties
