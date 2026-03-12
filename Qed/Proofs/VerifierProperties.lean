import Qed.Verifier

set_option autoImplicit false

namespace Qed.Proofs.VerifierProperties

open Qed.Verifier

-- ============================================================
-- isIdentChar: Character classification
-- ============================================================

/-- isIdentChar checks the same character set used in isValidModuleName's
    per-part validation. This connects the boundary detection in containsSorry
    with the character validation in isValidModuleName. -/
theorem isIdentChar_eq_validModuleChar (c : Char) :
    isIdentChar c = (c.isAlpha || c.isDigit || c == '_' || c == '\'') := by
  unfold isIdentChar
  rfl

-- ============================================================
-- targetToModule: Module extraction from qualified names
-- ============================================================

/-- Complete characterization of targetToModule: returns `some m` if and only if
    the target has at least 2 dot-separated parts and `m` is the intercalation
    of all parts except the last (the theorem name segment). -/
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

/-- moduleToPath output always ends with ".lean". -/
theorem moduleToPath_ends_with_lean (module : String) :
    ∃ prefix_part, moduleToPath module = prefix_part ++ ".lean" := by
  unfold moduleToPath
  exact ⟨module.replace "." "/", rfl⟩

/-- Composing targetToModule and moduleToPath: the file path is derived
    from the dot-separated parts of the target (all but the last segment),
    with dots replaced by path separators. -/
theorem moduleToPath_of_targetToModule (target : String) (m : String)
    (h : targetToModule target = some m) :
    moduleToPath m =
      (String.intercalate "." ((target.splitOn ".").dropLast)).replace "." "/"
        ++ ".lean" := by
  unfold targetToModule at h
  simp at h
  unfold moduleToPath
  rw [h.2]

-- ============================================================
-- isValidModuleName: Shell injection prevention
-- ============================================================

/-- Complete characterization of isValidModuleName: returns true if and only if
    every dot-separated part is non-empty and contains only identifier characters
    (alphanumeric, underscore, or single quote).

    The only characters in the name are therefore drawn from
    {alpha, digit, '_', '\'', '.'} — since splitOn "." decomposes at every
    dot, and each segment is validated. This guarantees shell safety: the name
    cannot contain shell metacharacters, preventing injection when interpolated
    into `lake build {name}`. -/
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

-- ============================================================
-- containsSorry: Sorry detection with word boundaries
-- ============================================================

/-- Complete characterization of containsSorry: returns true if and only if
    "sorry" appears as a substring AND at least one occurrence has non-identifier
    (or absent) characters on both sides. This guarantees both no false negatives
    (standalone "sorry" is always detected) and no false positives ("sorry" inside
    identifiers like "sorryHandler" is not flagged). -/
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
