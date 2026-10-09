import Qed.Verifier

set_option autoImplicit false

namespace Qed.Proofs.VerifierProperties

open Qed.Verifier

/-! # Proof-target resolution and sorry detection -/

/-- `targetToModule` yields the dot-separated prefix of a proof target exactly
    when the target has a module part and a theorem part. -/
theorem targetToModule_iff (target : String) (m : String) :
    targetToModule target = some m ↔
    (target.splitOn ".").length ≥ 2 ∧
    m = String.intercalate "." (target.splitOn ".").dropLast := by
  constructor
  · intro h
    unfold targetToModule at h
    simp at h
    exact ⟨h.1, h.2.symm⟩
  · intro ⟨hlen, hval⟩
    unfold targetToModule
    simp
    exact ⟨hlen, hval.symm⟩

/-- An accepted module name is drawn entirely from {alpha, digit, `_`, `'`, `.`},
    so it cannot carry shell metacharacters into `lake build {name}`. -/
theorem isValidModuleName_iff (name : String) :
    isValidModuleName name = true ↔
    (name.splitOn ".").length > 0 ∧
    ∀ part, part ∈ name.splitOn "." →
      part.isEmpty = false ∧
      (part.all fun c => c.isAlpha || c.isDigit || c == '_' || c == '\'') = true := by
  constructor
  · intro h
    unfold isValidModuleName at h
    simp [Bool.and_eq_true] at h
    exact h
  · intro ⟨hlen, hparts⟩
    unfold isValidModuleName
    simp [Bool.and_eq_true]
    exact ⟨hlen, hparts⟩

/-- `sorry` is detected exactly when it occurs on identifier boundaries: no
    missed standalone `sorry`, and no false positive inside `sorryHandler`. -/
theorem containsSorry_iff (contents : String) :
    containsSorry contents = true ↔
    let parts := contents.splitOn "sorry"
    parts.length ≥ 2 ∧
    (List.range (parts.length - 1)).any (fun i =>
      let before := parts[i]!
      let after := parts[i + 1]!
      let boundaryBefore := match before.back? with
        | none => true
        | some c => !isIdentChar c
      let boundaryAfter := match after.front? with
        | none => true
        | some c => !isIdentChar c
      boundaryBefore && boundaryAfter) = true := by
  unfold containsSorry
  simp only []
  constructor
  · intro h
    split at h
    · simp at h
    · exact ⟨by omega, h⟩
  · intro ⟨hlen, hany⟩
    split
    · omega
    · exact hany

end Qed.Proofs.VerifierProperties
