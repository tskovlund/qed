import Qed.Types
import Qed.Parser
import Qed.Serializer

set_option autoImplicit false

namespace Qed.Proofs.Roundtrip

open Qed Qed.Parser Qed.Serializer Lean

/-! # Serializer–Parser roundtrip proofs

The main result: `parseFromJson (specToJson spec) = .ok spec` for well-formed
specs. This guarantees the serializer and parser agree on every field — any
future mismatch breaks the proof at compile time.

## Strategy

Lean 4.28.0 uses `Std.TreeMap` for JSON objects internally. `simp` cannot reduce
`TreeMap.get?` on known keys, but `rfl` (kernel reduction) can. We use a
two-layer approach:

1. **Levels 1–4** (atomic roundtrips): case-split on all `Option` fields so
   the kernel sees a fully concrete JSON object, then close with `rfl`.
2. **Level 5** (spec-level): define JSON shape helpers whose lookup behaviour
   is provable by `rfl`, then `simp` with those helpers to reduce the outer
   `parseFromJson` structure while `rw [criteria_list_roundtrip]` handles the
   universally-quantified criteria list. -/

-- ═══════════════════════════════════════════════════════════════════
-- JSON shape helpers — abstract over TreeMap to give simp rewrite rules
-- ═══════════════════════════════════════════════════════════════════

/-- Verify-mode spec JSON: just name + criteria. -/
private def verifyJson (name : String) (criteriaArr : Array Json) : Json :=
  Json.mkObj [("name", Json.str name), ("criteria", Json.arr criteriaArr)]

/-- WorkerLoop-mode spec JSON: name + criteria + worker + loop config. -/
private def workerLoopJson (name : String) (criteriaArr : Array Json)
    (workerJson : Json) (maxIter stuckThresh : Nat) : Json :=
  Json.mkObj [("name", Json.str name), ("criteria", Json.arr criteriaArr),
    ("worker", workerJson), ("maxIterations", Lean.toJson maxIter),
    ("stuckThreshold", Lean.toJson stuckThresh)]

-- Verify-mode lookups (all provable by rfl — kernel reduces TreeMap on concrete keys)
private theorem vj_name (n : String) (a : Array Json) :
    requireString (verifyJson n a) "name" = .ok n := by rfl
private theorem vj_criteria (n : String) (a : Array Json) :
    (verifyJson n a).getObjVal? "criteria" = .ok (Json.arr a) := by rfl
private theorem vj_no_worker (n : String) (a : Array Json) :
    (verifyJson n a).getObjVal? "worker" = .error "property not found: worker" := by rfl
private theorem vj_no_maxIter (n : String) (a : Array Json) :
    ((verifyJson n a).getObjVal? "maxIterations").isOk = false := by rfl
private theorem vj_no_stuckThresh (n : String) (a : Array Json) :
    ((verifyJson n a).getObjVal? "stuckThreshold").isOk = false := by rfl

-- WorkerLoop-mode lookups (default parameter d is irrelevant — field is always present)
private theorem wj_name (n : String) (a : Array Json) (w : Json) (mi st : Nat) :
    requireString (workerLoopJson n a w mi st) "name" = .ok n := by rfl
private theorem wj_criteria (n : String) (a : Array Json) (w : Json) (mi st : Nat) :
    (workerLoopJson n a w mi st).getObjVal? "criteria" = .ok (Json.arr a) := by rfl
private theorem wj_worker (n : String) (a : Array Json) (w : Json) (mi st : Nat) :
    (workerLoopJson n a w mi st).getObjVal? "worker" = .ok w := by rfl
private theorem wj_maxIter (n : String) (a : Array Json) (w : Json) (mi st d : Nat) :
    optionalNat (workerLoopJson n a w mi st) "maxIterations" d = .ok mi := by rfl
private theorem wj_stuckThresh (n : String) (a : Array Json) (w : Json) (mi st d : Nat) :
    optionalNat (workerLoopJson n a w mi st) "stuckThreshold" d = .ok st := by rfl

-- specToJson shape lemmas (rfl: list append + Json.mkObj reduce definitionally)
private theorem specToJson_verify (name : String) (criteria : List AcceptanceCriterion) :
    specToJson { name, mode := .verify, criteria } =
    verifyJson name (criteria.map criterionToJson).toArray := by rfl

-- ═══════════════════════════════════════════════════════════════════
-- Level 1: CiSchedule roundtrip
-- ═══════════════════════════════════════════════════════════════════

/-- parseCiSchedule inverts ciScheduleToString for every constructor. -/
theorem ciSchedule_roundtrip (cs : CiSchedule) :
    parseCiSchedule (ciScheduleToString cs) = .ok cs := by
  cases cs <;> rfl

-- ═══════════════════════════════════════════════════════════════════
-- Level 2: VerifyType roundtrip
-- ═══════════════════════════════════════════════════════════════════

/-- parseVerifyType inverts verifyTypeToJson for every constructor.
    The agent case needs case-splitting on the optional command field
    because it changes the JSON object structure. -/
theorem verifyType_roundtrip (vt : VerifyType) :
    parseVerifyType (verifyTypeToJson vt) = .ok vt := by
  cases vt with
  | command run timeout => rfl
  | agent prompt model command => cases command <;> rfl
  | property run timeout => rfl
  | proof prover target => rfl
  | human instruction => rfl

-- ═══════════════════════════════════════════════════════════════════
-- Level 3: AcceptanceCriterion roundtrip
-- ═══════════════════════════════════════════════════════════════════

/-- parseCriterion inverts criterionToJson. Full case-split on all verify type
    constructors × CI schedules × skip × optional fields so the kernel can reduce
    every TreeMap lookup. -/
theorem criterion_roundtrip (criterion : AcceptanceCriterion) :
    parseCriterion (criterionToJson criterion) = .ok criterion := by
  cases criterion with
  | mk description verify ci skip =>
    cases verify with
    | command run timeout => cases ci <;> cases skip <;> rfl
    | agent prompt model command => cases command <;> (cases ci <;> cases skip <;> rfl)
    | property run timeout => cases ci <;> cases skip <;> rfl
    | proof prover target => cases ci <;> cases skip <;> rfl
    | human instruction => cases ci <;> cases skip <;> rfl

-- ═══════════════════════════════════════════════════════════════════
-- Level 4: WorkerConfig roundtrip
-- ═══════════════════════════════════════════════════════════════════

/-- parseWorkerConfig inverts workerConfigToJson for all configs. -/
theorem workerConfig_roundtrip (worker : WorkerConfig) :
    parseWorkerConfig (workerConfigToJson worker) = .ok worker := by
  cases worker with
  | mk command prompt model workdir timeout =>
    cases command <;> cases prompt <;> rfl

-- ═══════════════════════════════════════════════════════════════════
-- Helper: lift element-wise roundtrip to List.mapM
-- ═══════════════════════════════════════════════════════════════════

/-- If parsing inverts serialization for each element, mapM inverts map. -/
theorem criteria_list_roundtrip (criteria : List AcceptanceCriterion) :
    (criteria.map criterionToJson).mapM parseCriterion = Except.ok criteria := by
  induction criteria with
  | nil => rfl
  | cons head tail ih =>
    simp only [List.map, List.mapM_cons, criterion_roundtrip, bind, Except.bind]
    rw [ih]; rfl

-- ═══════════════════════════════════════════════════════════════════
-- Level 5: Full Spec roundtrip
-- ═══════════════════════════════════════════════════════════════════

/-- parseFromJson inverts specToJson for verify-mode specs with non-empty criteria. -/
theorem spec_verify_roundtrip (name : String) (criteria : List AcceptanceCriterion)
    (hne : criteria ≠ []) :
    parseFromJson (specToJson { name, mode := .verify, criteria }) =
      .ok { name, mode := .verify, criteria } := by
  have hcr := criteria_list_roundtrip criteria
  rw [specToJson_verify]
  unfold parseFromJson
  simp only [vj_name, vj_criteria, vj_no_worker,
    vj_no_maxIter, vj_no_stuckThresh,
    bind, Except.bind, hcr, List.isEmpty]
  cases criteria with
  | nil => exact absurd rfl hne
  | cons _ _ => rfl

set_option maxHeartbeats 800000 in
/-- parseFromJson inverts specToJson for workerLoop-mode specs.
    Requires at least one of command/prompt to be present (well-formedness). -/
theorem spec_workerLoop_roundtrip (name : String) (criteria : List AcceptanceCriterion)
    (worker : WorkerConfig) (loopConfig : LoopConfig)
    (hw : worker.command.isSome ∨ worker.prompt.isSome) :
    parseFromJson (specToJson { name, mode := .workerLoop worker loopConfig, criteria }) =
      .ok { name, mode := .workerLoop worker loopConfig, criteria } := by
  have hcr := criteria_list_roundtrip criteria
  cases worker with
  | mk command prompt model workdir timeout =>
    cases loopConfig with
    | mk maxIterations stuckThreshold =>
      cases command <;> cases prompt
      · -- (none, none): contradicts hw
        simp [Option.isSome] at hw
      all_goals {
        -- After case-splitting, specToJson reduces to workerLoopJson shape
        show parseFromJson (workerLoopJson name (criteria.map criterionToJson).toArray
          (workerConfigToJson _) maxIterations stuckThreshold) = _
        unfold parseFromJson
        simp only [wj_name, wj_criteria, wj_worker, wj_maxIter, wj_stuckThresh,
          workerConfig_roundtrip, hcr, bind, Except.bind, Option.isNone]
        simp
      }

/-- **Main roundtrip theorem:** parsing the serialized JSON of any well-formed
spec recovers the original spec exactly. Well-formed means:
- Verify-mode specs have at least one criterion
- Worker configs have at least one of command or prompt -/
theorem spec_roundtrip (spec : Spec)
    (h : spec.mode = .verify → spec.criteria ≠ [])
    (hw : ∀ w lc, spec.mode = .workerLoop w lc → w.command.isSome ∨ w.prompt.isSome) :
    parseFromJson (specToJson spec) = .ok spec := by
  cases hmode : spec.mode with
  | verify =>
    have hne := h hmode
    have : spec = { name := spec.name, mode := .verify, criteria := spec.criteria } := by
      cases spec; simp_all
    rw [this]
    exact spec_verify_roundtrip spec.name spec.criteria hne
  | workerLoop worker loopConfig =>
    have hww := hw worker loopConfig hmode
    have : spec = { name := spec.name, mode := .workerLoop worker loopConfig, criteria := spec.criteria } := by
      cases spec; simp_all
    rw [this]
    exact spec_workerLoop_roundtrip spec.name spec.criteria worker loopConfig hww

end Qed.Proofs.Roundtrip
