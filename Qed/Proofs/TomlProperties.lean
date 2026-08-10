import Qed.TomlParser

set_option autoImplicit false

namespace Qed.Proofs.TomlProperties

open Qed.TomlParser

/-! # TOML table construction -/

/-- A fresh key is appended, leaving existing entries untouched. -/
theorem setNested_no_duplicate_at_leaf (pairs : List (String × TomlValue))
    (key : String) (value : TomlValue)
    (h_unique : pairs.any (fun (k, _) => k == key) = false) :
    setNested pairs [key] value = .ok (pairs ++ [(key, value)]) := by
  unfold setNested
  simp [h_unique]

/-- A duplicate key is an error rather than a silent overwrite, so a spec file
    that defines the same key twice fails loudly. -/
theorem setNested_rejects_duplicate (pairs : List (String × TomlValue))
    (key : String) (value : TomlValue)
    (h_dup : pairs.any (fun (k, _) => k == key) = true) :
    ∃ error, setNested pairs [key] value = .error error := by
  unfold setNested
  simp [h_dup]

end Qed.Proofs.TomlProperties
