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
    parseRequiredString (verifyJson n a) "name" = .ok n := by rfl
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
    parseRequiredString (workerLoopJson n a w mi st) "name" = .ok n := by rfl
private theorem wj_criteria (n : String) (a : Array Json) (w : Json) (mi st : Nat) :
    (workerLoopJson n a w mi st).getObjVal? "criteria" = .ok (Json.arr a) := by rfl
private theorem wj_worker (n : String) (a : Array Json) (w : Json) (mi st : Nat) :
    (workerLoopJson n a w mi st).getObjVal? "worker" = .ok w := by rfl
private theorem wj_maxIter (n : String) (a : Array Json) (w : Json) (mi st d : Nat) :
    parseOptionalNat (workerLoopJson n a w mi st) "maxIterations" d = .ok mi := by rfl
private theorem wj_stuckThresh (n : String) (a : Array Json) (w : Json) (mi st d : Nat) :
    parseOptionalNat (workerLoopJson n a w mi st) "stuckThreshold" d = .ok st := by rfl

-- specToJson shape lemmas (rfl: list append + Json.mkObj reduce definitionally)
private theorem specToJson_verify (name : String) (criteria : List AcceptanceCriterion) :
    specToJson { name, mode := .verify, criteria } =
    verifyJson name (criteria.map criterionToJson).toArray := by rfl

-- ═══════════════════════════════════════════════════════════════════
-- Lock field roundtrip helpers
-- ═══════════════════════════════════════════════════════════════════

/-- parseStringItem succeeds on Json.str values. -/
private theorem parseStringItem_str (field : String) (s : String) :
    parseStringItem field (Json.str s) = Except.ok s := by rfl

/-- mapM parseStringItem over Json.str values recovers the original list. -/
private theorem lock_mapM (patterns : List String) (field : String) :
    List.mapM (parseStringItem field) (patterns.map Json.str) = Except.ok patterns := by
  induction patterns with
  | nil => rfl
  | cons _ _ ih =>
    simp only [List.map, List.mapM_cons, parseStringItem_str, bind, Except.bind, ih]; rfl

/-- parseOptionalStringList inverts stringListToJson when the field is present. -/
private theorem lock_field_roundtrip (patterns : List String) (json : Json)
    (h : json.getObjVal? "lock" = .ok (Json.arr (patterns.map Json.str).toArray)) :
    parseOptionalStringList json "lock" = Except.ok (some patterns) := by
  unfold parseOptionalStringList
  rw [h]
  simp only [bind, Except.bind, lock_mapM]

-- ═══════════════════════════════════════════════════════════════════
-- Command-with-lock and property-with-lock JSON shapes
-- ═══════════════════════════════════════════════════════════════════

/-- Command verify type JSON with lock field. -/
private def cmdLockJson (run : String) (timeout : Nat) (lockArr : Json) : Json :=
  Json.mkObj [("type", Json.str "command"), ("run", Json.str run),
    ("timeout", Lean.toJson timeout), ("lock", lockArr)]

private theorem cl_type (r : String) (t : Nat) (l : Json) :
    parseRequiredString (cmdLockJson r t l) "type" = .ok "command" := by rfl
private theorem cl_run (r : String) (t : Nat) (l : Json) :
    parseRequiredString (cmdLockJson r t l) "run" = .ok r := by rfl
private theorem cl_timeout (r : String) (t : Nat) (l : Json) (d : Nat) :
    parseOptionalNat (cmdLockJson r t l) "timeout" d = .ok t := by rfl
private theorem cl_lock (r : String) (t : Nat) (l : Json) :
    (cmdLockJson r t l).getObjVal? "lock" = .ok l := by rfl

private theorem vtj_command_lock (run : String) (timeout : Nat) (patterns : List String) :
    verifyTypeToJson (.command run timeout (some patterns)) =
    cmdLockJson run timeout (stringListToJson patterns) := by rfl

private theorem cl_parseOptionalStringList (r : String) (t : Nat) (patterns : List String) :
    parseOptionalStringList (cmdLockJson r t (stringListToJson patterns)) "lock" =
      Except.ok (some patterns) := by
  apply lock_field_roundtrip
  unfold stringListToJson
  exact cl_lock r t (Json.arr (patterns.map Json.str).toArray)

/-- Property verify type JSON with lock field. -/
private def propLockJson (run : String) (timeout : Nat) (lockArr : Json) : Json :=
  Json.mkObj [("type", Json.str "property"), ("run", Json.str run),
    ("timeout", Lean.toJson timeout), ("lock", lockArr)]

private theorem pl_type (r : String) (t : Nat) (l : Json) :
    parseRequiredString (propLockJson r t l) "type" = .ok "property" := by rfl
private theorem pl_run (r : String) (t : Nat) (l : Json) :
    parseRequiredString (propLockJson r t l) "run" = .ok r := by rfl
private theorem pl_timeout (r : String) (t : Nat) (l : Json) (d : Nat) :
    parseOptionalNat (propLockJson r t l) "timeout" d = .ok t := by rfl
private theorem pl_lock (r : String) (t : Nat) (l : Json) :
    (propLockJson r t l).getObjVal? "lock" = .ok l := by rfl

private theorem vtj_property_lock (run : String) (timeout : Nat) (patterns : List String) :
    verifyTypeToJson (.property run timeout (some patterns)) =
    propLockJson run timeout (stringListToJson patterns) := by rfl

private theorem pl_parseOptionalStringList (r : String) (t : Nat) (patterns : List String) :
    parseOptionalStringList (propLockJson r t (stringListToJson patterns)) "lock" =
      Except.ok (some patterns) := by
  apply lock_field_roundtrip
  unfold stringListToJson
  exact pl_lock r t (Json.arr (patterns.map Json.str).toArray)

-- ═══════════════════════════════════════════════════════════════════
-- Criterion JSON shape helpers — abstract over the verify JSON value
-- ═══════════════════════════════════════════════════════════════════

/-- Criterion JSON without skip field. -/
private def critJsonNoSkip (desc : String) (vt : Json) (sched : String) : Json :=
  Json.mkObj [("description", Json.str desc), ("verify", vt),
    ("schedule", Json.str sched)]

/-- Criterion JSON with skip field. -/
private def critJsonSkip (desc : String) (vt : Json) (sched : String)
    (skipReason : String) : Json :=
  Json.mkObj [("description", Json.str desc), ("verify", vt),
    ("schedule", Json.str sched), ("skip", Json.str skipReason)]

-- criterionToJson shape lemmas
private theorem criterionToJson_no_skip (desc : String) (vt : VerifyType) (sched : Schedule) :
    criterionToJson { description := desc, verify := vt, schedule := sched, skip := none } =
    critJsonNoSkip desc (verifyTypeToJson vt) (scheduleToString sched) := by rfl

private theorem criterionToJson_skip (desc : String) (vt : VerifyType) (sched : Schedule)
    (reason : String) :
    criterionToJson { description := desc, verify := vt, schedule := sched, skip := some reason } =
    critJsonSkip desc (verifyTypeToJson vt) (scheduleToString sched) reason := by rfl

-- Lookup lemmas for critJsonNoSkip
private theorem cjn_desc (d : String) (v : Json) (s : String) :
    parseRequiredString (critJsonNoSkip d v s) "description" = .ok d := by rfl
private theorem cjn_verify (d : String) (v : Json) (s : String) :
    (critJsonNoSkip d v s).getObjVal? "verify" = .ok v := by rfl
private theorem cjn_schedule (d : String) (v : Json) (s : String) :
    (critJsonNoSkip d v s).getObjValAs? String "schedule" = .ok s := by rfl

-- Lookup lemmas for critJsonSkip
private theorem cjs_desc (d : String) (v : Json) (s : String) (r : String) :
    parseRequiredString (critJsonSkip d v s r) "description" = .ok d := by rfl
private theorem cjs_verify (d : String) (v : Json) (s : String) (r : String) :
    (critJsonSkip d v s r).getObjVal? "verify" = .ok v := by rfl
private theorem cjs_schedule (d : String) (v : Json) (s : String) (r : String) :
    (critJsonSkip d v s r).getObjValAs? String "schedule" = .ok s := by rfl
private theorem cjs_skip (d : String) (v : Json) (s : String) (r : String) :
    (critJsonSkip d v s r).getObjValAs? String "skip" = .ok r := by rfl

-- Skip match lemmas: prove the match result directly (avoids needing the
-- exact getObjValAs? error message which involves typeclass reduction)
private theorem cjn_skip_match (d : String) (v : Json) (s : String) :
    (match (critJsonNoSkip d v s).getObjValAs? String "skip" with
      | .ok value => some value | .error _ => none) = @none String := by rfl
private theorem cjs_skip_match (d : String) (v : Json) (s : String) (r : String) :
    (match (critJsonSkip d v s r).getObjValAs? String "skip" with
      | .ok value => some value | .error _ => none) = some r := by rfl

-- ═══════════════════════════════════════════════════════════════════
-- Level 1: Schedule roundtrip
-- ═══════════════════════════════════════════════════════════════════

/-- parseSchedule inverts scheduleToString for every constructor. -/
theorem schedule_roundtrip (cs : Schedule) :
    parseSchedule (scheduleToString cs) = .ok cs := by
  cases cs <;> rfl

-- ═══════════════════════════════════════════════════════════════════
-- Level 2: VerifyType roundtrip
-- ═══════════════════════════════════════════════════════════════════

/-- parseVerifyType inverts verifyTypeToJson for every constructor.
    The agent case needs case-splitting on the optional command field
    and command/property need case-splitting on the optional lock field
    because they change the JSON object structure. -/
theorem verifyType_roundtrip (vt : VerifyType) :
    parseVerifyType (verifyTypeToJson vt) = .ok vt := by
  cases vt with
  | command run timeout lock =>
    cases lock with
    | none => rfl
    | some patterns =>
      rw [vtj_command_lock]
      unfold parseVerifyType
      simp only [cl_type, cl_run, cl_timeout, cl_parseOptionalStringList,
        bind, Except.bind]
  | agent prompt model command => cases command <;> rfl
  | property run timeout lock =>
    cases lock with
    | none => rfl
    | some patterns =>
      rw [vtj_property_lock]
      unfold parseVerifyType
      simp only [pl_type, pl_run, pl_timeout, pl_parseOptionalStringList,
        bind, Except.bind]
  | proof prover target => rfl
  | human instruction => rfl

-- ═══════════════════════════════════════════════════════════════════
-- Level 3: AcceptanceCriterion roundtrip
-- ═══════════════════════════════════════════════════════════════════

/-- parseCriterion inverts criterionToJson. Uses verifyType_roundtrip and
    schedule_roundtrip to avoid case-splitting on VerifyType internals. -/
theorem criterion_roundtrip (criterion : AcceptanceCriterion) :
    parseCriterion (criterionToJson criterion) = .ok criterion := by
  cases criterion with
  | mk description verify schedule skip =>
    have hvt := verifyType_roundtrip verify
    have hsc := schedule_roundtrip schedule
    cases skip with
    | none =>
      rw [criterionToJson_no_skip]
      unfold parseCriterion
      simp only [cjn_desc, cjn_verify, hvt, bind, Except.bind,
        cjn_schedule, hsc]
      rfl
    | some reason =>
      rw [criterionToJson_skip]
      unfold parseCriterion
      simp only [cjs_desc, cjs_verify, hvt, bind, Except.bind,
        cjs_schedule, hsc]
      rfl

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
