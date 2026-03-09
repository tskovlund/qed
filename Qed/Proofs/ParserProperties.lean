import Qed.Types
import Qed.Parser

set_option autoImplicit false

namespace Qed.Proofs.ParserProperties

open Qed Qed.Parser

-- 1. parseCiSchedule is complete over valid inputs

/-- `parseCiSchedule` accepts exactly the three valid CI schedule strings.
If it succeeds, the input was one of "always", "trunk", or "manual". -/
theorem parseCiSchedule_complete (s : String) (cs : CiSchedule)
    (h : parseCiSchedule s = .ok cs) :
    s = "always" ∨ s = "trunk" ∨ s = "manual" := by
  simp [parseCiSchedule] at h
  split at h <;> simp_all

-- 2. parseCiSchedule maps each string to the correct constructor

theorem parseCiSchedule_always : parseCiSchedule "always" = .ok CiSchedule.always := by
  rfl

theorem parseCiSchedule_trunk : parseCiSchedule "trunk" = .ok CiSchedule.trunk := by
  rfl

theorem parseCiSchedule_manual : parseCiSchedule "manual" = .ok CiSchedule.manual := by
  rfl

-- 3. parseCiSchedule rejects invalid inputs

/-- Any string that isn't "always", "trunk", or "manual" produces an error. -/
theorem parseCiSchedule_rejects_invalid (s : String)
    (h1 : s ≠ "always") (h2 : s ≠ "trunk") (h3 : s ≠ "manual") :
    ∃ e, parseCiSchedule s = .error e := by
  unfold parseCiSchedule
  split
  · simp_all
  · simp_all
  · simp_all
  · exact ⟨_, rfl⟩

end Qed.Proofs.ParserProperties
