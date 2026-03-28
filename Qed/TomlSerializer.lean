import Qed.Types
import Qed.TomlParser
import Qed.Serializer

set_option autoImplicit false

namespace Qed.TomlSerializer

open Qed Qed.TomlParser

/-! # Spec → TOML serialization

Two layers:
1. **specToTomlPairs** — `Spec → List (String × TomlValue)`. Roundtrip-proven:
   `toJson (.table (specToTomlPairs spec)) = specToJson spec`.
2. **renderToml** — `List (String × TomlValue) → String`. Tested, not proven.

The composition `specToToml := renderToml ∘ specToTomlPairs` gives us a
TOML serializer whose semantic correctness is formally verified. -/

-- ============================================================================
-- Layer 1: Spec → TomlValue (roundtrip-proven against Serializer.specToJson)
-- ============================================================================

/-- Serialize a Schedule to its string representation.
    Must satisfy: `scheduleToTomlString s = Serializer.scheduleToString s`
    (identical — both formats use the same schedule names). -/
def scheduleToTomlString : Schedule → String
  | .always => "always"
  | .heavy => "heavy"
  | .manual => "manual"

/-- Serialize a VerifyType to TOML key-value pairs (the `[criteria.verify]` table).
    Must satisfy: `toJson (.table (verifyTypeToTomlPairs vt)) = verifyTypeToJson vt` -/
def verifyTypeToTomlPairs (verifyType : VerifyType) : List (String × TomlValue) := sorry

/-- Serialize an AcceptanceCriterion to TOML key-value pairs.
    Must satisfy: `toJson (.table (criterionToTomlPairs c)) = criterionToJson c` -/
def criterionToTomlPairs (criterion : AcceptanceCriterion) : List (String × TomlValue) := sorry

/-- Serialize a WorkerConfig to TOML key-value pairs (the `[worker]` table).
    Must satisfy: `toJson (.table (workerConfigToTomlPairs w)) = workerConfigToJson w` -/
def workerConfigToTomlPairs (worker : WorkerConfig) : List (String × TomlValue) := sorry

/-- Serialize a Spec to top-level TOML key-value pairs.
    This is the roundtrip-proven layer.
    Must satisfy: `toJson (.table (specToTomlPairs spec)) = specToJson spec` -/
def specToTomlPairs (spec : Spec) : List (String × TomlValue) := sorry

-- ============================================================================
-- Layer 2: TomlValue → String (tested, not proven)
-- ============================================================================

/-- Render a TOML value as a string. Strings are quoted, multi-line strings
    (containing newlines) use triple-quote syntax. -/
def renderValue (value : TomlValue) : String := sorry

/-- Render a list of TOML key-value pairs as a TOML document string.
    Handles top-level scalars, `[table]` sections, and `[[array]]` sections. -/
def renderToml (pairs : List (String × TomlValue)) : String := sorry

/-- Serialize a Spec to a TOML document string.
    Composition: `specToTomlPairs` (proven) then `renderToml` (tested). -/
def specToToml (spec : Spec) : String := renderToml (specToTomlPairs spec)

end Qed.TomlSerializer
