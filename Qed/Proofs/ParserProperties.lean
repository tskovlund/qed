import Qed.Types
import Qed.Parser

set_option autoImplicit false

namespace Qed.Proofs.ParserProperties

open Qed Qed.Parser

/-- Complete characterization of parseSchedule: returns `.ok cs` if and only if
    the input string and result constructor match one of the three valid pairs.
    This guarantees both acceptance (every valid string maps to the right
    constructor) and rejection (invalid strings always produce errors). -/
theorem parseSchedule_iff (s : String) (cs : Schedule) :
    parseSchedule s = .ok cs ↔
    (s = "always" ∧ cs = .always) ∨
    (s = "heavy" ∧ cs = .heavy) ∨
    (s = "manual" ∧ cs = .manual) := by
  constructor
  · intro h
    simp [parseSchedule] at h
    split at h <;> simp_all
  · intro h
    rcases h with ⟨hs, hcs⟩ | ⟨hs, hcs⟩ | ⟨hs, hcs⟩ <;>
      (subst hs; subst hcs; rfl)

end Qed.Proofs.ParserProperties
