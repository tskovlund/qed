import Qed.Types
import Qed.Parser
import Qed.Serializer
import Qed.TomlParser
import Qed.TomlSerializer
import Qed.Proofs.Roundtrip

set_option autoImplicit false

namespace Qed.Proofs.TomlRoundtrip

open Qed Qed.Parser Qed.Serializer Qed.TomlParser Qed.TomlSerializer Lean

/-! # TOML Serializer–Parser roundtrip proofs

The main result: the TOML serializer produces `TomlValue`s whose JSON
representation matches the JSON serializer exactly. Combined with the
proven `spec_roundtrip`, this gives:

    parseFromJson (toJson (.table (specToTomlPairs spec))) = .ok spec

## Strategy

Prove `toJson (.table (specToTomlPairs spec)) = specToJson spec` by
structural induction, mirroring the 5-level hierarchy in `Roundtrip.lean`:

1. Schedule: `scheduleToTomlString` = `scheduleToString`
2. VerifyType: `toJson` on TOML pairs = `verifyTypeToJson`
3. Criterion: `toJson` on TOML pairs = `criterionToJson`
4. WorkerConfig: `toJson` on TOML pairs = `workerConfigToJson`
5. Spec: `toJson` on TOML pairs = `specToJson`

Each level reduces to showing that the TOML serializer constructs the
same key-value pairs (as `TomlValue`s) that the JSON serializer constructs
(as `Json` values), and `toJson` maps between them faithfully. -/

-- ═══════════════════════════════════════════════════════════════════
-- Helpers
-- ═══════════════════════════════════════════════════════════════════

/-- Converting a list of TomlValue.str back through toJsonList yields Json.str. -/
private theorem toJsonList_map_str (strings : List String) :
    TomlParser.toJsonList (strings.map TomlValue.str) = strings.map Json.str := by
  induction strings with
  | nil => rfl
  | cons head tail ih =>
    simp only [List.map, TomlParser.toJsonList, TomlParser.toJson, ih]

/-- `Lean.toJson` for `Nat` reduces to `Json.num`. Needed because `simp`
    cannot reduce the typeclass application. -/
private theorem lean_toJson_nat (n : Nat) :
    Lean.toJson n = Json.num (JsonNumber.fromInt (Int.ofNat n)) := rfl

-- ═══════════════════════════════════════════════════════════════════
-- Level 1: Schedule — TOML and JSON serializers produce the same string
-- ═══════════════════════════════════════════════════════════════════

/-- The TOML and JSON schedule serializers are identical. -/
theorem schedule_toml_eq_json (schedule : Schedule) :
    scheduleToTomlString schedule = Serializer.scheduleToString schedule := by
  cases schedule <;> rfl

-- ═══════════════════════════════════════════════════════════════════
-- Level 2: VerifyType — TOML pairs convert to the same JSON
-- ═══════════════════════════════════════════════════════════════════

/-- Converting TOML verify-type pairs to JSON produces the same result
    as the JSON serializer. -/
theorem verifyType_toml_json_eq (verifyType : VerifyType) :
    TomlParser.toJson (.table (verifyTypeToTomlPairs verifyType)) =
    Serializer.verifyTypeToJson verifyType := by
  cases verifyType with
  | command run timeout lock =>
    cases lock with
    | none => rfl
    | some patterns =>
      unfold verifyTypeToTomlPairs Serializer.verifyTypeToJson Serializer.stringListToJson
      simp only [List.cons_append, List.nil_append,
                  TomlParser.toJson, TomlParser.toJsonPairs,
                  toJsonList_map_str, lean_toJson_nat]
  | agent prompt model command timeout =>
    cases command <;> rfl
  | property run timeout lock =>
    cases lock with
    | none => rfl
    | some patterns =>
      unfold verifyTypeToTomlPairs Serializer.verifyTypeToJson Serializer.stringListToJson
      simp only [List.cons_append, List.nil_append,
                  TomlParser.toJson, TomlParser.toJsonPairs,
                  toJsonList_map_str, lean_toJson_nat]
  | proof prover target => rfl
  | human instruction => rfl

-- ═══════════════════════════════════════════════════════════════════
-- Level 3: AcceptanceCriterion — TOML pairs convert to the same JSON
-- ═══════════════════════════════════════════════════════════════════

/-- Converting TOML criterion pairs to JSON produces the same result
    as the JSON serializer. -/
theorem criterion_toml_json_eq (criterion : AcceptanceCriterion) :
    TomlParser.toJson (.table (criterionToTomlPairs criterion)) =
    Serializer.criterionToJson criterion := by
  cases criterion with
  | mk description verify schedule skip =>
    have hvt : Json.mkObj (TomlParser.toJsonPairs (verifyTypeToTomlPairs verify)) =
        Serializer.verifyTypeToJson verify := verifyType_toml_json_eq verify
    have hsc := schedule_toml_eq_json schedule
    cases skip with
    | none =>
      simp only [criterionToTomlPairs, Serializer.criterionToJson,
                  TomlParser.toJson, TomlParser.toJsonPairs, hvt, hsc]
    | some reason =>
      unfold criterionToTomlPairs Serializer.criterionToJson
      simp only [List.cons_append, List.nil_append,
                  TomlParser.toJson, TomlParser.toJsonPairs, hvt, hsc]

/-- Lift element-wise criterion equivalence to lists (for the criteria array). -/
theorem criteria_list_toml_json_eq (criteria : List AcceptanceCriterion) :
    TomlParser.toJsonList (criteria.map fun c => .table (criterionToTomlPairs c)) =
    criteria.map Serializer.criterionToJson := by
  induction criteria with
  | nil => rfl
  | cons head tail ih =>
    simp only [List.map, TomlParser.toJsonList, criterion_toml_json_eq, ih]

-- ═══════════════════════════════════════════════════════════════════
-- Level 4: WorkerConfig — TOML pairs convert to the same JSON
-- ═══════════════════════════════════════════════════════════════════

/-- Converting TOML worker config pairs to JSON produces the same result
    as the JSON serializer. -/
theorem workerConfig_toml_json_eq (worker : WorkerConfig) :
    TomlParser.toJson (.table (workerConfigToTomlPairs worker)) =
    Serializer.workerConfigToJson worker := by
  cases worker with
  | mk command prompt model workdir timeout =>
    cases command <;> cases prompt <;> rfl

-- ═══════════════════════════════════════════════════════════════════
-- Level 5: Full Spec — the bridge theorem
-- ═══════════════════════════════════════════════════════════════════

/-- **Bridge theorem:** the TOML serializer produces the same JSON as the
    JSON serializer. This is the core equivalence that enables the roundtrip. -/
theorem spec_toml_json_eq (spec : Spec) :
    TomlParser.toJson (.table (specToTomlPairs spec)) =
    Serializer.specToJson spec := by
  cases spec with
  | mk name mode criteria =>
    have hcr := criteria_list_toml_json_eq criteria
    cases mode with
    | verify =>
      simp only [specToTomlPairs, Serializer.specToJson,
                  TomlParser.toJson, TomlParser.toJsonPairs, hcr]
    | workerLoop worker loopConfig =>
      -- hwc at the reduced form (toJson (.table x) ≡ Json.mkObj (toJsonPairs x))
      have hwc : Json.mkObj (TomlParser.toJsonPairs (workerConfigToTomlPairs worker)) =
          Serializer.workerConfigToJson worker := workerConfig_toml_json_eq worker
      unfold specToTomlPairs Serializer.specToJson
      simp only [List.cons_append, List.nil_append,
                  TomlParser.toJson, TomlParser.toJsonPairs, hcr, hwc,
                  lean_toJson_nat]

/-- **Main roundtrip theorem:** parsing the TOML-serialized spec (via JSON
    intermediary) recovers the original spec. Composes `spec_toml_json_eq`
    with the proven JSON roundtrip. -/
theorem toml_spec_roundtrip (spec : Spec)
    (h : spec.mode = .verify → spec.criteria ≠ [])
    (hw : ∀ w lc, spec.mode = .workerLoop w lc → w.command.isSome ∨ w.prompt.isSome) :
    parseFromJson (TomlParser.toJson (.table (specToTomlPairs spec))) = .ok spec := by
  rw [spec_toml_json_eq]
  exact Roundtrip.spec_roundtrip spec h hw

end Qed.Proofs.TomlRoundtrip
