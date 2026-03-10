import Qed.Types

set_option autoImplicit false

namespace Qed.Proofs.TypeProperties

open Qed

-- 1. isTerminal decidability

/-- Every LoopState is either terminal or not — the terminal predicate is
decidable. This follows from the exhaustive pattern match in `isTerminal`. -/
theorem isTerminal_decidable (state : LoopState) :
    state.isTerminal = true ∨ state.isTerminal = false := by
  cases state <;> simp [LoopState.isTerminal]

-- 2. isPassed characterization

/-- `isPassed` returns true if and only if the result is a `.pass`. -/
theorem isPassed_iff_pass (result : VerificationResult) :
    result.isPassed = true ↔ ∃ details : String, result = .pass details := by
  cases result <;> simp [VerificationResult.isPassed]

-- 3. isFailed characterization

/-- `isFailed` returns true if and only if the result is a `.fail`. -/
theorem isFailed_iff_fail (result : VerificationResult) :
    result.isFailed = true ↔ ∃ details : String, result = .fail details := by
  cases result <;> simp [VerificationResult.isFailed]

-- 4. isPassed and isFailed are mutually exclusive

/-- No VerificationResult is both passed and failed. -/
theorem passed_and_failed_exclusive (result : VerificationResult) :
    ¬ (result.isPassed = true ∧ result.isFailed = true) := by
  cases result <;> simp [VerificationResult.isPassed, VerificationResult.isFailed]

-- 5. VerificationResult exhaustive partition

/-- Every VerificationResult is exactly one of pass, fail, needsHuman, or skipped. -/
theorem result_exhaustive (result : VerificationResult) :
    (∃ d, result = .pass d) ∨ (∃ d, result = .fail d) ∨
    (∃ i, result = .needsHuman i) ∨ (∃ r, result = .skipped r) := by
  cases result with
  | pass d => exact .inl ⟨d, rfl⟩
  | fail d => exact .inr (.inl ⟨d, rfl⟩)
  | needsHuman i => exact .inr (.inr (.inl ⟨i, rfl⟩))
  | skipped r => exact .inr (.inr (.inr ⟨r, rfl⟩))

-- 6. Combined: complete partition (spec-level theorem)
--
-- Combines (2)-(5) into a single statement: every result is exactly one
-- variant, and the isPassed/isFailed predicates agree with the constructor.

/-- Every VerificationResult falls into exactly one of four categories.
For each category, isPassed and isFailed correctly reflect the variant.
This is the complete partition of the result space — the foundation for
allPassed correctness (OutputCorrectness.allPassed_iff_no_failures). -/
theorem result_complete_partition (result : VerificationResult) :
    (∃ d, result = .pass d) ∧ result.isPassed = true ∧ result.isFailed = false
  ∨ (∃ d, result = .fail d) ∧ result.isPassed = false ∧ result.isFailed = true
  ∨ (∃ i, result = .needsHuman i) ∧ result.isPassed = false ∧ result.isFailed = false
  ∨ (∃ r, result = .skipped r) ∧ result.isPassed = false ∧ result.isFailed = false := by
  cases result with
  | pass d => exact .inl ⟨⟨d, rfl⟩, rfl, rfl⟩
  | fail d => exact .inr (.inl ⟨⟨d, rfl⟩, rfl, rfl⟩)
  | needsHuman i => exact .inr (.inr (.inl ⟨⟨i, rfl⟩, rfl, rfl⟩))
  | skipped r => exact .inr (.inr (.inr ⟨⟨r, rfl⟩, rfl, rfl⟩))

end Qed.Proofs.TypeProperties
