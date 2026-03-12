import Qed.Types

set_option autoImplicit false

namespace Qed.Proofs.TypeProperties

open Qed

-- 1. isTerminal characterization

/-- isTerminal returns true if and only if the state is one of the five
terminal states: passed, stuck, maxIterationsReached, escalated, or
integrityViolation. Non-terminal states (ready, workerRunning, verifying)
return false. -/
theorem isTerminal_iff (state : LoopState) :
    state.isTerminal = true ↔
    (∃ n, state = .passed n) ∨
    (∃ n fs, state = .stuck n fs) ∨
    (∃ n, state = .maxIterationsReached n) ∨
    (∃ n, state = .escalated n) ∨
    (∃ n, state = .integrityViolation n) := by
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

-- 3a. isSkipped characterization

/-- `isSkipped` returns true if and only if the result is a `.skipped`. -/
theorem isSkipped_iff_skipped (result : VerificationResult) :
    result.isSkipped = true ↔ ∃ reason : String, result = .skipped reason := by
  cases result <;> simp [VerificationResult.isSkipped]

-- 4. isPassed, isFailed, isSkipped are pairwise mutually exclusive

/-- No VerificationResult satisfies more than one of isPassed, isFailed, isSkipped. -/
theorem predicates_mutually_exclusive (result : VerificationResult) :
    ¬ (result.isPassed = true ∧ result.isFailed = true) ∧
    ¬ (result.isPassed = true ∧ result.isSkipped = true) ∧
    ¬ (result.isFailed = true ∧ result.isSkipped = true) := by
  cases result <;> simp [VerificationResult.isPassed, VerificationResult.isFailed, VerificationResult.isSkipped]

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
For each category, isPassed, isFailed, and isSkipped correctly reflect the
variant. This is the complete partition of the result space — the foundation
for allPassed correctness (OutputCorrectness.allPassed_iff_no_failures). -/
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
