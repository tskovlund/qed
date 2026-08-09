import Qed.Ignore

set_option autoImplicit false

namespace Qed.Proofs.IgnoreProperties

open Qed Qed.Ignore

/-! # .qedignore parsing and pattern precedence properties

`Ignore.lean` had no proof coverage. Two of its three pure functions are
total and provable:

* `parseIgnoreFile` — a `splitOn`/`map`/`filter` pipeline. The theorems below
  pin down its output contract: no blank lines, no comment lines.
* `shouldIgnore` — the last-matching-pattern-wins precedence rule, including
  `!` negation. These proofs treat `fnmatch` as an abstract predicate, so they
  hold regardless of how globbing itself behaves.

`fnmatch` itself is deliberately *not* covered: its inner loop `fnmatchGo` is
`partial` (star backtracking resets the pattern pointer while advancing the
string pointer, so it is not structurally decreasing). A `partial def` is
opaque to the kernel — it has no equational lemmas — so no property of
`fnmatch` can be stated until it is re-expressed with a fuel parameter or a
well-founded measure. See `docs/proven-properties.md` for that follow-up. -/

-- ═══════════════════════════════════════════════════════════════════
-- parseIgnoreFile output contract
-- ═══════════════════════════════════════════════════════════════════

/-- Every pattern `parseIgnoreFile` returns is non-empty — blank lines are
    dropped, so downstream code never matches against the empty pattern. -/
theorem parseIgnoreFile_no_empty (contents : String) :
    ∀ pattern ∈ parseIgnoreFile contents, pattern.isEmpty = false := by
  intro pattern hmem
  unfold parseIgnoreFile at hmem
  rw [List.mem_filter] at hmem
  have hcond := hmem.2
  simp only [Bool.and_eq_true, Bool.not_eq_true'] at hcond
  exact hcond.1

/-- No pattern `parseIgnoreFile` returns is a comment — `#` lines are dropped
    before any pattern matching happens. -/
theorem parseIgnoreFile_no_comments (contents : String) :
    ∀ pattern ∈ parseIgnoreFile contents, pattern.startsWith "#" = false := by
  intro pattern hmem
  unfold parseIgnoreFile at hmem
  rw [List.mem_filter] at hmem
  have hcond := hmem.2
  simp only [Bool.and_eq_true, Bool.not_eq_true'] at hcond
  exact hcond.2

-- ═══════════════════════════════════════════════════════════════════
-- shouldIgnore precedence
-- ═══════════════════════════════════════════════════════════════════

/-- With no patterns nothing is ignored — an absent or empty `.qedignore`
    file ignores nothing rather than defaulting to some built-in set. -/
theorem shouldIgnore_empty (name : String) : shouldIgnore [] name = false := rfl

/-- A trailing non-negated pattern that matches forces the name to be ignored,
    whatever the earlier patterns decided. This is the "last matching pattern
    wins" rule, in its positive direction. -/
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

/-- A trailing negated pattern (`!foo`) that matches un-ignores the name,
    whatever the earlier patterns decided — the negative direction of the same
    rule. -/
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
