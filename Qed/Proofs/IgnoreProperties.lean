import Qed.Ignore

set_option autoImplicit false

namespace Qed.Proofs.IgnoreProperties

open Qed Qed.Ignore

/-! # .qedignore parsing, glob semantics, and pattern precedence -/

/-- A pattern character with no special meaning to `matchGlob`. -/
def isLiteralChar (c : Char) : Bool := c != '*' && c != '?' && c != '['

-- ═══════════════════════════════════════════════════════════════════
-- parseIgnoreFile output contract
-- ═══════════════════════════════════════════════════════════════════

/-- Blank lines are dropped, so no downstream match is ever attempted against
    the empty pattern. -/
theorem parseIgnoreFile_no_empty (contents : String) :
    ∀ pattern ∈ parseIgnoreFile contents, pattern.isEmpty = false := by
  intro pattern hmem
  unfold parseIgnoreFile at hmem
  rw [List.mem_filter] at hmem
  have hcond := hmem.2
  simp only [Bool.and_eq_true, Bool.not_eq_true'] at hcond
  exact hcond.1

/-- Comment lines are dropped before any pattern matching happens. -/
theorem parseIgnoreFile_no_comments (contents : String) :
    ∀ pattern ∈ parseIgnoreFile contents, pattern.startsWith "#" = false := by
  intro pattern hmem
  unfold parseIgnoreFile at hmem
  rw [List.mem_filter] at hmem
  have hcond := hmem.2
  simp only [Bool.and_eq_true, Bool.not_eq_true'] at hcond
  exact hcond.2

-- ═══════════════════════════════════════════════════════════════════
-- Glob semantics
-- ═══════════════════════════════════════════════════════════════════

/-- **`*` semantics:** a leading `*` matches exactly when some suffix of the
    name matches the rest of the pattern. -/
theorem matchGlob_star_iff_suffix (patRest str : List Char) :
    matchGlob ('*' :: patRest) str = true ↔
      ∃ suffix, suffix <:+ str ∧ matchGlob patRest suffix = true := by
  induction str with
  | nil =>
    constructor
    · intro h
      exact ⟨[], List.nil_suffix, by simpa [matchGlob] using h⟩
    · rintro ⟨suffix, hsuf, hm⟩
      have hnil : suffix = [] := List.eq_nil_of_suffix_nil hsuf
      subst hnil
      simpa [matchGlob] using hm
  | cons c s ih =>
    rw [show matchGlob ('*' :: patRest) (c :: s)
          = (matchGlob patRest (c :: s) || matchGlob ('*' :: patRest) s) from by
            simp [matchGlob]]
    simp only [Bool.or_eq_true]
    constructor
    · rintro (h | h)
      · exact ⟨c :: s, List.suffix_refl _, h⟩
      · obtain ⟨suffix, hsuf, hm⟩ := ih.mp h
        exact ⟨suffix, hsuf.trans (List.suffix_cons c s), hm⟩
    · rintro ⟨suffix, hsuf, hm⟩
      rcases List.suffix_cons_iff.mp hsuf with rfl | hsuf'
      · exact Or.inl hm
      · exact Or.inr (ih.mpr ⟨suffix, hsuf', hm⟩)

/-- A bare `*` matches every name, path separators included — so `*` in a
    `.qedignore` ignores the whole tree, not just its top level. -/
theorem star_matches_everything (str : List Char) : matchGlob ['*'] str = true := by
  induction str with
  | nil => simp [matchGlob]
  | cons c s ih => simp [matchGlob, ih]

/-- **`?` semantics:** exactly one character, and never a path separator. -/
theorem question_matches_one (patRest str : List Char) (c : Char) :
    matchGlob ('?' :: patRest) (c :: str) = true ↔
      c ≠ '/' ∧ matchGlob patRest str = true := by
  simp [matchGlob]

private theorem literal_ne {p : Char} (hlit : isLiteralChar p = true) :
    p ≠ '*' ∧ p ≠ '?' ∧ p ≠ '[' := by
  unfold isLiteralChar at hlit
  simp only [Bool.and_eq_true, bne_iff_ne, ne_eq] at hlit
  exact ⟨hlit.1.1, hlit.1.2, hlit.2⟩

private theorem matchGlob_literal_nil {p : Char} (ps : List Char)
    (hlit : isLiteralChar p = true) : matchGlob (p :: ps) [] = false := by
  have h := literal_ne hlit
  rw [matchGlob]
  all_goals simp_all

private theorem matchGlob_literal_cons {p : Char} (ps str : List Char) (c : Char)
    (hlit : isLiteralChar p = true) :
    matchGlob (p :: ps) (c :: str) = (p == c && matchGlob ps str) := by
  have h := literal_ne hlit
  rw [matchGlob]
  all_goals simp_all

/-- **Literal semantics:** a pattern with no wildcards is an exact-match test —
    it matches its own text and nothing else. -/
theorem literal_matches_iff (pattern str : List Char)
    (hlit : pattern.all isLiteralChar = true) :
    matchGlob pattern str = true ↔ pattern = str := by
  induction pattern generalizing str with
  | nil => cases str <;> simp [matchGlob]
  | cons p ps ih =>
    simp only [List.all_cons, Bool.and_eq_true] at hlit
    cases str with
    | nil => simp [matchGlob_literal_nil ps hlit.1]
    | cons c cs =>
      rw [matchGlob_literal_cons ps cs c hlit.1]
      simp only [Bool.and_eq_true, beq_iff_eq]
      rw [ih cs hlit.2]
      constructor
      · rintro ⟨rfl, rfl⟩; rfl
      · intro h; injection h with h1 h2; exact ⟨h1, h2⟩

/-- A literal prefix followed by `*` matches every name carrying that prefix. -/
theorem literal_star_matches_prefix (literal rest : List Char)
    (hlit : literal.all isLiteralChar = true) :
    matchGlob (literal ++ ['*']) (literal ++ rest) = true := by
  induction literal with
  | nil => simpa using star_matches_everything rest
  | cons p ps ih =>
    simp only [List.all_cons, Bool.and_eq_true] at hlit
    simp only [List.cons_append]
    rw [matchGlob_literal_cons (ps ++ ['*']) (ps ++ rest) p hlit.1]
    simp [ih hlit.2]

-- ═══════════════════════════════════════════════════════════════════
-- shouldIgnore precedence
-- ═══════════════════════════════════════════════════════════════════

/-- Last matching pattern wins, positive direction: a trailing plain pattern
    that matches ignores the name whatever the earlier patterns decided. -/
theorem shouldIgnore_append_positive (patterns : List String)
    (pattern name : String) (hneg : pattern.startsWith "!" = false)
    (hmatch : fnmatch pattern name = true) :
    shouldIgnore (patterns ++ [pattern]) name = true := by
  unfold shouldIgnore
  suffices h : ∀ (remaining : List String) (ignored : Bool),
      shouldIgnore.go name (remaining ++ [pattern]) ignored = true by
    exact h patterns false
  intro remaining
  induction remaining with
  | nil =>
    intro ignored
    simp [List.nil_append, shouldIgnore.go, hneg, hmatch]
  | cons head tail ih =>
    intro ignored
    simp only [List.cons_append, shouldIgnore.go]
    split <;> split <;> apply ih

/-- Last matching pattern wins, negative direction: a trailing `!` pattern that
    matches un-ignores the name whatever the earlier patterns decided. -/
theorem shouldIgnore_append_negated (patterns : List String)
    (pattern name : String) (hneg : pattern.startsWith "!" = true)
    (hmatch : fnmatch (pattern.drop 1).toString name = true) :
    shouldIgnore (patterns ++ [pattern]) name = false := by
  unfold shouldIgnore
  suffices h : ∀ (remaining : List String) (ignored : Bool),
      shouldIgnore.go name (remaining ++ [pattern]) ignored = false by
    exact h patterns false
  intro remaining
  induction remaining with
  | nil =>
    intro ignored
    simp only [List.nil_append, shouldIgnore.go, hneg, hmatch, if_true]
  | cons head tail ih =>
    intro ignored
    simp only [List.cons_append, shouldIgnore.go]
    split <;> split <;> apply ih

end Qed.Proofs.IgnoreProperties
