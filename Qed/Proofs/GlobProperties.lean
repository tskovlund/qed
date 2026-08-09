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
    isValidGlobPattern pattern = (!pattern.isEmpty && pattern.all isGlobSafeChar) := rfl

end Qed.Proofs.GlobProperties
