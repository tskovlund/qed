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
-- Level 1: Schedule — TOML and JSON serializers produce the same string
-- ═══════════════════════════════════════════════════════════════════

/-- The TOML and JSON schedule serializers are identical. -/
theorem schedule_toml_eq_json (schedule : Schedule) :
    scheduleToTomlString schedule = Serializer.scheduleToString schedule := sorry

-- ═══════════════════════════════════════════════════════════════════
-- Level 2: VerifyType — TOML pairs convert to the same JSON
-- ═══════════════════════════════════════════════════════════════════

/-- Converting TOML verify-type pairs to JSON produces the same result
    as the JSON serializer. -/
theorem verifyType_toml_json_eq (verifyType : VerifyType) :
    TomlParser.toJson (.table (verifyTypeToTomlPairs verifyType)) =
    Serializer.verifyTypeToJson verifyType := sorry

-- ═══════════════════════════════════════════════════════════════════
-- Level 3: AcceptanceCriterion — TOML pairs convert to the same JSON
-- ═══════════════════════════════════════════════════════════════════

/-- Converting TOML criterion pairs to JSON produces the same result
    as the JSON serializer. -/
theorem criterion_toml_json_eq (criterion : AcceptanceCriterion) :
    TomlParser.toJson (.table (criterionToTomlPairs criterion)) =
    Serializer.criterionToJson criterion := sorry

/-- Lift element-wise criterion equivalence to lists (for the criteria array). -/
theorem criteria_list_toml_json_eq (criteria : List AcceptanceCriterion) :
    TomlParser.toJsonList (criteria.map fun c => .table (criterionToTomlPairs c)) =
    criteria.map Serializer.criterionToJson := sorry

-- ═══════════════════════════════════════════════════════════════════
-- Level 4: WorkerConfig — TOML pairs convert to the same JSON
-- ═══════════════════════════════════════════════════════════════════

/-- Converting TOML worker config pairs to JSON produces the same result
    as the JSON serializer. -/
theorem workerConfig_toml_json_eq (worker : WorkerConfig) :
    TomlParser.toJson (.table (workerConfigToTomlPairs worker)) =
    Serializer.workerConfigToJson worker := sorry

-- ═══════════════════════════════════════════════════════════════════
-- Level 5: Full Spec — the bridge theorem
-- ═══════════════════════════════════════════════════════════════════

/-- **Bridge theorem:** the TOML serializer produces the same JSON as the
    JSON serializer. This is the core equivalence that enables the roundtrip. -/
theorem spec_toml_json_eq (spec : Spec) :
    TomlParser.toJson (.table (specToTomlPairs spec)) =
    Serializer.specToJson spec := sorry

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
