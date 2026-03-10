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

/-- Every VerificationResult is exactly one of pass, fail, needsHuman, or skipped.
This is the exhaustive direction — combined with mutual exclusivity (4), it gives
a complete partition of the result space. -/
theorem result_exhaustive (result : VerificationResult) :
    (∃ d, result = .pass d) ∨ (∃ d, result = .fail d) ∨
    (∃ i, result = .needsHuman i) ∨ (∃ r, result = .skipped r) := by
  cases result with
  | pass d => exact .inl ⟨d, rfl⟩
  | fail d => exact .inr (.inl ⟨d, rfl⟩)
  | needsHuman i => exact .inr (.inr (.inl ⟨i, rfl⟩))
  | skipped r => exact .inr (.inr (.inr ⟨r, rfl⟩))

end Qed.Proofs.TypeProperties
