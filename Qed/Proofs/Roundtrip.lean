import Qed.Types
import Qed.Parser
import Qed.Serializer

set_option autoImplicit false

namespace Qed.Proofs.Roundtrip

open Qed Qed.Parser Qed.Serializer Lean

/-! # Serializer–Parser roundtrip proofs

The main result: `parseFromJson (specToJson spec) = .ok spec` for well-formed
specs. This guarantees the serializer and parser agree on every field — any
future mismatch breaks the proof at compile time. -/

-- Level 1: CiSchedule roundtrip

/-- parseCiSchedule inverts ciScheduleToString for every constructor. -/
theorem ciSchedule_roundtrip (cs : CiSchedule) :
    parseCiSchedule (ciScheduleToString cs) = .ok cs := by
  cases cs <;> rfl

-- Level 2: VerifyType roundtrip

/-- parseVerifyType inverts verifyTypeToJson for every constructor. -/
theorem verifyType_roundtrip (vt : VerifyType) :
    parseVerifyType (verifyTypeToJson vt) = .ok vt := by
  cases vt with
  | command run timeout =>
    simp [verifyTypeToJson, parseVerifyType, requireString, optionalNat,
      Json.mkObj, Json.getObjValAs?, Json.getObjVal?]
  | agent prompt model =>
    simp [verifyTypeToJson, parseVerifyType, requireString, optionalString,
      Json.mkObj, Json.getObjValAs?, Json.getObjVal?]
  | property run timeout =>
    simp [verifyTypeToJson, parseVerifyType, requireString, optionalNat,
      Json.mkObj, Json.getObjValAs?, Json.getObjVal?]
  | proof prover target =>
    simp [verifyTypeToJson, parseVerifyType, requireString,
      Json.mkObj, Json.getObjValAs?, Json.getObjVal?]
  | human instruction =>
    simp [verifyTypeToJson, parseVerifyType, requireString,
      Json.mkObj, Json.getObjValAs?, Json.getObjVal?]

-- Level 3: AcceptanceCriterion roundtrip

/-- parseCriterion inverts criterionToJson. -/
theorem criterion_roundtrip (criterion : AcceptanceCriterion) :
    parseCriterion (criterionToJson criterion) = .ok criterion := by
  simp [criterionToJson, parseCriterion, requireString,
    Json.mkObj, Json.getObjValAs?, Json.getObjVal?]
  constructor
  · exact verifyType_roundtrip criterion.verify
  · exact ciSchedule_roundtrip criterion.ci

-- Level 4: WorkerConfig roundtrip

/-- parseWorkerConfig inverts workerConfigToJson. -/
theorem workerConfig_roundtrip (worker : WorkerConfig) :
    parseWorkerConfig (workerConfigToJson worker) = .ok worker := by
  simp [workerConfigToJson, parseWorkerConfig, requireString, optionalString, optionalNat,
    Json.mkObj, Json.getObjValAs?, Json.getObjVal?]

-- Helper: lift element-wise roundtrip to List.mapM

/-- If parsing inverts serialization for each element, mapM inverts map. -/
theorem criteria_list_roundtrip (criteria : List AcceptanceCriterion) :
    (criteria.map criterionToJson).mapM parseCriterion = Except.ok criteria := by
  induction criteria with
  | nil => simp
  | cons head tail ih =>
    simp only [List.map, List.mapM_cons]
    simp [criterion_roundtrip head, ih]

-- Level 5: Full Spec roundtrip

/-- parseFromJson inverts specToJson for verify-mode specs with non-empty criteria. -/
theorem spec_verify_roundtrip (name : String) (criteria : List AcceptanceCriterion)
    (hne : criteria ≠ []) :
    parseFromJson (specToJson { name, mode := .verify, criteria }) =
      .ok { name, mode := .verify, criteria } := by
  simp [specToJson, parseFromJson, requireString,
    Json.mkObj, Json.getObjValAs?, Json.getObjVal?]
  constructor
  · simp [Array.mapM]
    exact criteria_list_roundtrip criteria
  · simp [List.isEmpty]
    cases criteria with
    | nil => contradiction
    | cons _ _ => simp

/-- parseFromJson inverts specToJson for workerLoop-mode specs. -/
theorem spec_workerLoop_roundtrip (name : String) (criteria : List AcceptanceCriterion)
    (worker : WorkerConfig) (loopConfig : LoopConfig) :
    parseFromJson (specToJson { name, mode := .workerLoop worker loopConfig, criteria }) =
      .ok { name, mode := .workerLoop worker loopConfig, criteria } := by
  simp [specToJson, parseFromJson, requireString, optionalNat,
    Json.mkObj, Json.getObjValAs?, Json.getObjVal?]
  constructor
  · simp [Array.mapM]
    exact criteria_list_roundtrip criteria
  · exact workerConfig_roundtrip worker

/-- **Main roundtrip theorem:** parsing the serialized JSON of any well-formed
spec recovers the original spec exactly. Well-formed means verify-mode specs
have at least one criterion (the parser rejects empty verify-mode specs). -/
theorem spec_roundtrip (spec : Spec)
    (h : spec.mode = .verify → spec.criteria ≠ []) :
    parseFromJson (specToJson spec) = .ok spec := by
  cases hmode : spec.mode with
  | verify =>
    have hne := h hmode
    have : spec = { name := spec.name, mode := .verify, criteria := spec.criteria } := by
      cases spec; simp_all
    rw [this]
    exact spec_verify_roundtrip spec.name spec.criteria hne
  | workerLoop worker loopConfig =>
    have : spec = { name := spec.name, mode := .workerLoop worker loopConfig, criteria := spec.criteria } := by
      cases spec; simp_all
    rw [this]
    exact spec_workerLoop_roundtrip spec.name spec.criteria worker loopConfig

end Qed.Proofs.Roundtrip
