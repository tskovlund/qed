import Qed.Ignore

set_option autoImplicit false

namespace Qed.Proofs.IgnoreProperties

open Qed Qed.Ignore

/-! # .qedignore parsing and pattern precedence

The precedence theorems treat `fnmatch` as an abstract predicate, so they hold
however globbing itself behaves. -/

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
