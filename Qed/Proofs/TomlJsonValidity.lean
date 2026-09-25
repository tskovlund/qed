import Qed.TomlParser

set_option autoImplicit false

namespace Qed.Proofs.TomlJsonValidity

open Qed.TomlParser

/-! # TOML → JSON error propagation

The conversion never invents a result and never swallows a parse error. -/

/-- A converted document was really parsed as TOML first. -/
theorem tomlToJson_ok_implies_parseDoc_ok (input : String) (json : String)
    (h : tomlToJson input = .ok json) :
    ∃ pairs, parseDoc input = .ok pairs := by
  unfold tomlToJson at h
  match hparse : parseDoc input with
  | .ok pairs => exact ⟨pairs, rfl⟩
  | .error _ => simp [hparse] at h

/-- A parse failure surfaces as a conversion failure rather than an empty
    document. -/
theorem parseDoc_error_implies_tomlToJson_error (input : String) (error : ErrorInfo)
    (h : parseDoc input = .error error) :
    ∃ message, tomlToJson input = .error message := by
  unfold tomlToJson
  simp [h]

end Qed.Proofs.TomlJsonValidity
