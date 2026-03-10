import Qed.Types
import Qed.Parser

set_option autoImplicit false

namespace Qed.Proofs.ParserProperties

open Qed Qed.Parser

-- 1. parseSchedule is complete over valid inputs

/-- `parseSchedule` accepts exactly the three valid schedule strings.
If it succeeds, the input was one of "always", "local", or "manual". -/
theorem parseSchedule_complete (s : String) (cs : Schedule)
    (h : parseSchedule s = .ok cs) :
    s = "always" ∨ s = "local" ∨ s = "manual" := by
  simp [parseSchedule] at h
  split at h <;> simp_all

-- 2. parseSchedule maps each string to the correct constructor

theorem parseSchedule_always : parseSchedule "always" = .ok Schedule.always := by
  rfl

theorem parseSchedule_local : parseSchedule "local" = .ok Schedule.local := by
  rfl

theorem parseSchedule_manual : parseSchedule "manual" = .ok Schedule.manual := by
  rfl

-- 3. parseSchedule rejects invalid inputs

/-- Any string that isn't "always", "local", or "manual" produces an error. -/
theorem parseSchedule_rejects_invalid (s : String)
    (h1 : s ≠ "always") (h2 : s ≠ "local") (h3 : s ≠ "manual") :
    ∃ e, parseSchedule s = .error e := by
  unfold parseSchedule
  split
  · simp_all
  · simp_all
  · simp_all
  · exact ⟨_, rfl⟩

end Qed.Proofs.ParserProperties
