import Qed.TomlParser

set_option autoImplicit false

namespace Qed.Proofs.TomlProperties

open Qed.TomlParser

-- 1. setNested never introduces duplicate keys at the leaf level

/-- If the key doesn't already exist, setNested inserts it at the end. -/
theorem setNested_no_duplicate_at_leaf (pairs : List (String × TomlValue))
    (key : String) (value : TomlValue)
    (h_unique : pairs.any (fun (k, _) => k == key) = false) :
    setNested pairs [key] value = .ok (pairs ++ [(key, value)]) := by
  unfold setNested
  simp [h_unique]

/-- If the key already exists, setNested returns an error at the leaf level. -/
theorem setNested_rejects_duplicate (pairs : List (String × TomlValue))
    (key : String) (value : TomlValue)
    (h_dup : pairs.any (fun (k, _) => k == key) = true) :
    ∃ error, setNested pairs [key] value = .error error := by
  unfold setNested
  simp [h_dup]

-- 2. setNested on empty key path always errors

/-- An empty key path is always rejected. -/
theorem setNested_empty_keys (pairs : List (String × TomlValue)) (value : TomlValue) :
    ∃ error, setNested pairs [] value = .error error := by
  unfold setNested
  exact ⟨_, rfl⟩

-- 3. appendArray on empty key path always errors

/-- appendArray on an empty key path always errors. -/
theorem appendArray_empty_keys (pairs : List (String × TomlValue)) :
    ∃ error, appendArray pairs [] = .error error := by
  unfold appendArray
  exact ⟨_, rfl⟩

-- 4. appendArray creates a new single-element array when key is absent

/-- When appending to a non-existent single-segment key, a new array with one
empty table is created. -/
theorem appendArray_creates_new (pairs : List (String × TomlValue))
    (key : String)
    (h_absent : pairs.find? (fun (k, _) => k == key) = none) :
    appendArray pairs [key] = .ok (pairs ++ [(key, .array [.table []])]) := by
  unfold appendArray
  simp [h_absent]

end Qed.Proofs.TomlProperties
