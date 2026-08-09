import Qed.ContractLock

set_option autoImplicit false

namespace Qed.Proofs.GlobProperties

open Qed.ContractLock

/-! # Glob pattern safety properties

`ContractLock.expandGlob` splices a caller-supplied pattern into

```
bash -c 'shopt -s globstar nullglob; for f in {pattern}; do ... done'
```

which is itself handed to `/bin/sh -c`. The pattern therefore crosses two
shell layers, and `isValidGlobPattern` is the only barrier in front of it.
The source comment at the splice site asserts that the validator "rejects
quotes and all shell metacharacters" — these theorems discharge the character
half of that claim, so it is checked by the kernel rather than trusted. -/

/-- The character policy rejects every shell metacharacter that could break
    out of either quoting layer: the single quote that would close `bash -c`'s
    argument, command substitution, statement separators, redirections, and
    whitespace. -/
theorem isGlobSafeChar_rejects_metacharacters :
    ∀ c ∈ ['\'', '"', '$', '`', ';', '&', '|', '(', ')', '<', '>',
           ' ', '\t', '\n', '\\', '{', '}', '!', '#', '~'],
      isGlobSafeChar c = false := by decide

/-- The characters glob expansion actually needs are all accepted, so the
    policy above is not vacuously safe by rejecting everything. -/
theorem isGlobSafeChar_accepts_glob_syntax :
    ∀ c ∈ ['*', '?', '/', '.', '_', '-', '[', ']', 'a', 'Z', '0', '9'],
      isGlobSafeChar c = true := by decide

/-- The empty pattern is rejected — an empty `for f in` word list would make
    the generated bash loop iterate over nothing silently. -/
theorem isValidGlobPattern_empty : isValidGlobPattern "" = false := by decide

/-- `isValidGlobPattern` is exactly "non-empty, and every character satisfies
    the policy above". Stated so a future edit that inlines or widens the
    character set breaks this proof rather than passing silently. -/
theorem isValidGlobPattern_eq (pattern : String) :
    isValidGlobPattern pattern = (!pattern.isEmpty && pattern.toList.all isGlobSafeChar) := rfl

-- ═══════════════════════════════════════════════════════════════════
-- The main safety result
-- ═══════════════════════════════════════════════════════════════════

/-- **Main theorem:** an accepted pattern contains no character that could
    break out of either shell layer. This is the property the comment at the
    `expandGlob` splice site asserts, now discharged for whole patterns rather
    than one character at a time. -/
theorem isValidGlobPattern_excludes_metacharacters (pattern : String) (c : Char)
    (hvalid : isValidGlobPattern pattern = true) (hmem : c ∈ pattern.toList) :
    c ≠ '\'' ∧ c ≠ '"' ∧ c ≠ '$' ∧ c ≠ '`' ∧ c ≠ ';' ∧ c ≠ '&' ∧ c ≠ '|' ∧
    c ≠ '(' ∧ c ≠ ')' ∧ c ≠ '<' ∧ c ≠ '>' ∧ c ≠ ' ' ∧ c ≠ '\\' ∧ c ≠ '\n' := by
  unfold isValidGlobPattern at hvalid
  simp only [Bool.and_eq_true, List.all_eq_true] at hvalid
  have hsafe := hvalid.2 c hmem
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;>
    (rintro rfl; simp [isGlobSafeChar] at hsafe)

/-- A valid pattern is never empty, so `expandGlob` always builds a bash loop
    with a real word list. -/
theorem isValidGlobPattern_nonempty (pattern : String)
    (hvalid : isValidGlobPattern pattern = true) : pattern.isEmpty = false := by
  unfold isValidGlobPattern at hvalid
  simp only [Bool.and_eq_true, Bool.not_eq_true'] at hvalid
  exact hvalid.1

-- ═══════════════════════════════════════════════════════════════════
-- Concrete injection attempts
-- ═══════════════════════════════════════════════════════════════════

/-- Closing the `bash -c '...'` quote to append a command is rejected. -/
theorem rejects_quote_escape : isValidGlobPattern "foo'; rm -rf /" = false := by decide

/-- Command substitution is rejected, in both `$(…)` and backtick forms. -/
theorem rejects_command_substitution :
    isValidGlobPattern "$(whoami)" = false ∧
    isValidGlobPattern "`whoami`" = false := by decide

/-- Statement separators and pipelines are rejected. -/
theorem rejects_separators :
    isValidGlobPattern "a;b" = false ∧
    isValidGlobPattern "a|b" = false ∧
    isValidGlobPattern "a&b" = false := by decide

/-- The patterns qed's own specs actually use are accepted, so the validator is
    not rejecting everything. -/
theorem accepts_real_patterns :
    isValidGlobPattern "Qed/**/*.lean" = true ∧
    isValidGlobPattern "Tests/**/*.lean" = true := by decide

end Qed.Proofs.GlobProperties
