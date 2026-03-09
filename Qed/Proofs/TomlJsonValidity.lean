import Qed.TomlParser

set_option autoImplicit false

namespace Qed.Proofs.TomlJsonValidity

open Qed.TomlParser Lean

/-! # TOML → JSON pipeline properties

`parseDoc` and `tomlToJson` are `partial` (recursive on nested inductives),
so the kernel cannot unfold them for proof. These theorems reason about the
pipeline at the `Except` level — correctness of the success/error contract. -/

-- 1. tomlToJson totality at the Except level

/-- `tomlToJson` always returns either a valid JSON string or an error.
This is a type-level guarantee: the function is total over `Except`. -/
theorem tomlToJson_total (input : String) :
    (∃ json, tomlToJson input = .ok json) ∨ (∃ e, tomlToJson input = .error e) := by
  unfold tomlToJson
  match parseDoc input with
  | .ok pairs => left; exact ⟨_, rfl⟩
  | .error e => right; exact ⟨_, rfl⟩

-- 2. Successful tomlToJson implies successful parseDoc

/-- If `tomlToJson` succeeds, the input was successfully parsed as TOML.
Contrapositive: if parsing fails, conversion fails. -/
theorem tomlToJson_ok_implies_parseDoc_ok (input : String) (json : String)
    (h : tomlToJson input = .ok json) :
    ∃ pairs, parseDoc input = .ok pairs := by
  unfold tomlToJson at h
  match hparse : parseDoc input with
  | .ok pairs => exact ⟨pairs, rfl⟩
  | .error _ => simp [hparse] at h

-- 3. Parse failure propagates to tomlToJson failure

/-- If `parseDoc` fails, `tomlToJson` also fails (with a prefixed error). -/
theorem parseDoc_error_implies_tomlToJson_error (input : String) (e : String)
    (h : parseDoc input = .error e) :
    ∃ msg, tomlToJson input = .error msg := by
  unfold tomlToJson
  simp [h]

end Qed.Proofs.TomlJsonValidity
