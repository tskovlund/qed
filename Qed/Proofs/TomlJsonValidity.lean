import Qed.TomlParser

set_option autoImplicit false

namespace Qed.Proofs.TomlJsonValidity

open Qed.TomlParser Lean

/-! # TOML → JSON pipeline properties

`toJson` uses mutual recursion for termination through nested inductives
(List inside TomlValue). `parseDoc` is still `partial` — pipeline-level
proofs reason about it at the `Except` level. `toJson` proofs can now
unfold the conversion function directly. -/

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

-- 4. toJson structural correctness (unlocked by making toJson non-partial)

/-- `toJson` maps each TomlValue constructor to the correct Json constructor. -/
theorem toJson_str (v : String) : toJson (.str v) = Json.str v := by
  unfold toJson
  rfl

theorem toJson_int (v : Int) : toJson (.int v) = Json.num v := by
  unfold toJson
  rfl

theorem toJson_bool (v : Bool) : toJson (.bool v) = Json.bool v := by
  unfold toJson
  rfl

theorem toJson_table (pairs : List (String × TomlValue)) :
    toJson (.table pairs) = Json.mkObj (toJsonPairs pairs) := by
  unfold toJson
  rfl

theorem toJson_array (items : List TomlValue) :
    toJson (.array items) = Json.arr (toJsonList items).toArray := by
  unfold toJson
  rfl

/-- An empty TOML table produces an empty JSON object. -/
theorem toJson_empty_table :
    toJson (.table []) = Json.mkObj [] := by
  unfold toJson toJsonPairs
  rfl

/-- An empty TOML array produces an empty JSON array. -/
theorem toJson_empty_array :
    toJson (.array []) = Json.arr #[] := by
  unfold toJson toJsonList
  rfl

end Qed.Proofs.TomlJsonValidity
