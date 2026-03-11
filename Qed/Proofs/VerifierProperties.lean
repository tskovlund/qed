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

/-- If the dot-separated split of the target produces fewer than 2 parts,
    targetToModule returns none. This covers strings with no dots. -/
theorem targetToModule_none_of_short_split (target : String)
    (h : (target.splitOn ".").length < 2) :
    targetToModule target = none := by
  unfold targetToModule
  simp [h]

/-- targetToModule returns some module name if and only if the target
    contains at least one dot (splitOn produces >= 2 parts). -/
theorem targetToModule_some_iff (target : String) :
    (∃ m, targetToModule target = some m) ↔ (target.splitOn ".").length ≥ 2 := by
  constructor
  · intro ⟨m, hm⟩
    unfold targetToModule at hm
    simp at hm
    exact hm.1
  · intro h
    unfold targetToModule
    simp
    omega

/-- When targetToModule returns some m, m is exactly the intercalation of all
    dot-separated parts except the last. -/
theorem targetToModule_value (target : String) (m : String)
    (h : targetToModule target = some m) :
    m = String.intercalate "." ((target.splitOn ".").dropLast) := by
  unfold targetToModule at h
  simp at h
  exact h.2.symm

-- Top-level property

/-- If targetToModule target returns some module name m, then:
    1. The target has at least 2 dot-separated parts (it contains a dot)
    2. m equals the intercalation of all parts except the last
    3. The parts decompose into m's parts followed by one final segment

    This proves targetToModule correctly extracts the module prefix —
    the original target is structurally the module name followed by a dot
    and the final (theorem name) segment. -/
theorem targetToModule_soundness (target : String) (m : String)
    (h : targetToModule target = some m) :
    let parts := target.splitOn "."
    parts.length ≥ 2 ∧
    m = String.intercalate "." parts.dropLast ∧
    ∃ lastSegment, parts = parts.dropLast ++ [lastSegment] := by
  unfold targetToModule at h
  simp at h
  refine ⟨h.1, h.2.symm, ?_⟩
  have hne : (target.splitOn ".") ≠ [] := by
    intro hempty; simp [hempty] at h
  exact ⟨(target.splitOn ".").getLast hne,
    (List.dropLast_concat_getLast hne).symm⟩

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
    (alphanumeric, underscore, or single quote). -/
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

/-- If any dot-separated part is empty (covers empty strings, leading dots,
    trailing dots, and double dots), isValidModuleName rejects the name. -/
theorem isValidModuleName_rejects_empty_part (name : String)
    (part : String) (hpart : part ∈ name.splitOn ".")
    (hempty : part.isEmpty = true) :
    isValidModuleName name = false := by
  cases hv : isValidModuleName name with
  | false => rfl
  | true =>
    exfalso
    unfold isValidModuleName at hv
    simp [Bool.and_eq_true] at hv
    exact absurd hempty (by rw [(hv.2 part hpart).1]; decide)

/-- If any dot-separated part contains a non-identifier character,
    isValidModuleName rejects the name. -/
theorem isValidModuleName_rejects_unsafe_part (name : String)
    (part : String) (hpart : part ∈ name.splitOn ".")
    (hunsafe : (part.all fun c =>
      c.isAlpha || c.isDigit || c == '_' || c == '\'') = false) :
    isValidModuleName name = false := by
  cases hv : isValidModuleName name with
  | false => rfl
  | true =>
    exfalso
    unfold isValidModuleName at hv
    simp [Bool.and_eq_true] at hv
    exact absurd hunsafe (by rw [(hv.2 part hpart).2]; decide)

-- Top-level property

/-- If isValidModuleName returns true, then:
    1. The name has at least one dot-separated segment
    2. No segment is empty (no leading dots, trailing dots, or double dots)
    3. Every segment contains only identifier characters

    The only characters in the name are therefore drawn from
    {alpha, digit, '_', '\'', '.'} — since splitOn "." decomposes at every
    dot, and each segment is validated. This guarantees shell safety: the name
    cannot contain shell metacharacters (spaces, semicolons, pipes, backticks,
    dollar signs, etc.), preventing injection when interpolated into
    `lake build {name}`. -/
theorem isValidModuleName_safe_chars (name : String)
    (h : isValidModuleName name = true) :
    (name.splitOn ".").length > 0 ∧
    (∀ part, part ∈ name.splitOn "." → part.isEmpty = false) ∧
    (∀ part, part ∈ name.splitOn "." →
      (part.all fun c =>
        c.isAlpha || c.isDigit || c == '_' || c == '\'') = true) := by
  unfold isValidModuleName at h
  simp [Bool.and_eq_true] at h
  exact ⟨h.1, fun part hp => (h.2 part hp).1, fun part hp => (h.2 part hp).2⟩

-- ============================================================
-- containsSorry: Sorry detection with word boundaries
-- ============================================================

/-- If "sorry" does not appear as a substring (splitOn produces only 1 part),
    containsSorry returns false. -/
theorem containsSorry_false_of_no_sorry (contents : String)
    (h : (contents.splitOn "sorry").length = 1) :
    containsSorry contents = false := by
  unfold containsSorry
  simp only []
  split
  · rfl
  · rename_i hge; omega

/-- If containsSorry returns true, then "sorry" appears as a substring
    (splitOn produces at least 2 parts). -/
theorem containsSorry_implies_sorry_present (contents : String)
    (h : containsSorry contents = true) :
    (contents.splitOn "sorry").length ≥ 2 := by
  unfold containsSorry at h
  simp only [] at h
  split at h
  · simp at h
  · rename_i hge; omega

/-- Complete characterization of containsSorry: it returns true if and only if
    "sorry" appears as a substring AND at least one occurrence has non-identifier
    (or absent) characters on both sides. -/
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

-- Top-level property: soundness (no false negatives for word-boundary matches)

/-- If "sorry" appears as a substring (parts.length >= 2) and at a specific
    occurrence the characters immediately before and after are not identifier
    characters (or absent — at string boundaries), then containsSorry returns
    true. This guarantees no false negatives: standalone "sorry" is always
    detected. -/
theorem containsSorry_soundness (contents : String)
    (hlen : (contents.splitOn "sorry").length ≥ 2)
    (i : Nat)
    (hi : i < (contents.splitOn "sorry").length - 1)
    (hbefore : (match (contents.splitOn "sorry")[i]!.back? with
      | none => true
      | some c => !isIdentChar c) = true)
    (hafter : (match (contents.splitOn "sorry")[i + 1]!.front? with
      | none => true
      | some c => !isIdentChar c) = true) :
    containsSorry contents = true := by
  unfold containsSorry
  simp only []
  split
  · omega
  · rw [List.any_eq_true]
    exact ⟨i, List.mem_range.mpr hi, by
      simp only [Bool.and_eq_true]
      exact ⟨hbefore, hafter⟩⟩

-- Top-level property: specificity (no false positives for identifiers)

/-- If at every occurrence of "sorry" as a substring, at least one adjacent
    character is an identifier character, then containsSorry returns false.
    This guarantees no false positives: "sorry" embedded in identifiers like
    "sorryHandler" or "notSorry" is not flagged. -/
theorem containsSorry_no_false_positive_for_identifiers (contents : String)
    (h : ∀ i, i < (contents.splitOn "sorry").length - 1 →
      ¬((match (contents.splitOn "sorry")[i]!.back? with
        | none => true
        | some c => !isIdentChar c) = true ∧
       (match (contents.splitOn "sorry")[i + 1]!.front? with
        | none => true
        | some c => !isIdentChar c) = true)) :
    containsSorry contents = false := by
  cases hv : containsSorry contents with
  | false => rfl
  | true =>
    exfalso
    unfold containsSorry at hv
    simp only [] at hv
    split at hv
    · simp at hv
    · rw [List.any_eq_true] at hv
      obtain ⟨i, hi, hcheck⟩ := hv
      rw [Bool.and_eq_true] at hcheck
      exact h i (List.mem_range.mp hi) hcheck

end Qed.Proofs.VerifierProperties
