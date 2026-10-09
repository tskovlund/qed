import Qed.ContractLock

set_option autoImplicit false

namespace Qed.Proofs.GlobProperties

open Qed.ContractLock

/-! # Glob pattern safety

`ContractLock.expandGlob` splices a caller-supplied pattern into a `bash -c`
argument that is itself handed to `/bin/sh -c`. `isValidGlobPattern` is the
only barrier in front of those two shell layers. -/

/-- **Main safety theorem:** no character of an accepted pattern can break out
    of either shell layer. -/
theorem isValidGlobPattern_excludes_metacharacters (pattern : String) (c : Char)
    (hvalid : isValidGlobPattern pattern = true) (hmem : c ∈ pattern.toList) :
    c ≠ '\'' ∧ c ≠ '"' ∧ c ≠ '$' ∧ c ≠ '`' ∧ c ≠ ';' ∧ c ≠ '&' ∧ c ≠ '|' ∧
    c ≠ '(' ∧ c ≠ ')' ∧ c ≠ '<' ∧ c ≠ '>' ∧ c ≠ ' ' ∧ c ≠ '\\' ∧ c ≠ '\n' := by
  unfold isValidGlobPattern at hvalid
  simp only [Bool.and_eq_true, List.all_eq_true] at hvalid
  have hsafe := hvalid.2 c hmem
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;>
    (rintro rfl; simp [isGlobSafeChar] at hsafe)

/-- An accepted pattern is never empty, so `expandGlob` always builds a loop
    over a real word list. -/
theorem isValidGlobPattern_nonempty (pattern : String)
    (hvalid : isValidGlobPattern pattern = true) : pattern.isEmpty = false := by
  unfold isValidGlobPattern at hvalid
  simp only [Bool.and_eq_true, Bool.not_eq_true'] at hvalid
  exact hvalid.1

/-- The patterns qed's own specs use are accepted, so the safety theorem above
    is not vacuous. -/
theorem accepts_real_patterns :
    isValidGlobPattern "Qed/**/*.lean" = true ∧
    isValidGlobPattern "Tests/**/*.lean" = true := by decide

end Qed.Proofs.GlobProperties
