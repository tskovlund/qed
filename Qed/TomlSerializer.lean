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
def verifyTypeToTomlPairs (verifyType : VerifyType) : List (String × TomlValue) :=
  match verifyType with
  | .command run timeout lock =>
    [("type", .str "command"),
     ("run", .str run),
     ("timeout", .int (Int.ofNat timeout))] ++
    (match lock with
    | some patterns => [("lock", .array (patterns.map .str))]
    | none => [])
  | .agent prompt model command timeout =>
    [("type", .str "agent"),
     ("prompt", .str prompt),
     ("model", .str model)] ++
    (match command with
    | some cmd => [("command", .str cmd)]
    | none => []) ++
    [("timeout", .int (Int.ofNat timeout))]
  | .property run timeout lock =>
    [("type", .str "property"),
     ("run", .str run),
     ("timeout", .int (Int.ofNat timeout))] ++
    (match lock with
    | some patterns => [("lock", .array (patterns.map .str))]
    | none => [])
  | .proof prover target =>
    [("type", .str "proof"),
     ("prover", .str prover),
     ("target", .str target)]
  | .human instruction =>
    [("type", .str "human"),
     ("instruction", .str instruction)]

/-- Serialize an AcceptanceCriterion to TOML key-value pairs.
    Must satisfy: `toJson (.table (criterionToTomlPairs c)) = criterionToJson c` -/
def criterionToTomlPairs (criterion : AcceptanceCriterion) : List (String × TomlValue) :=
  let base := [
    ("description", .str criterion.description),
    ("verify", .table (verifyTypeToTomlPairs criterion.verify)),
    ("schedule", .str (scheduleToTomlString criterion.schedule))]
  match criterion.skip with
  | some reason => base ++ [("skip", .str reason)]
  | none => base

/-- Serialize a WorkerConfig to TOML key-value pairs (the `[worker]` table).
    Must satisfy: `toJson (.table (workerConfigToTomlPairs w)) = workerConfigToJson w` -/
def workerConfigToTomlPairs (worker : WorkerConfig) : List (String × TomlValue) :=
  let base := [
    ("model", .str worker.model),
    ("workdir", .str worker.workdir),
    ("timeout", .int (Int.ofNat worker.timeout))]
  let withCommand := match worker.command with
    | some c => ("command", .str c) :: base
    | none => base
  match worker.prompt with
  | some p => ("prompt", .str p) :: withCommand
  | none => withCommand

/-- Serialize a Spec to top-level TOML key-value pairs.
    This is the roundtrip-proven layer.
    Must satisfy: `toJson (.table (specToTomlPairs spec)) = specToJson spec` -/
def specToTomlPairs (spec : Spec) : List (String × TomlValue) :=
  let base := [
    ("name", .str spec.name),
    ("criteria", .array (spec.criteria.map fun c => .table (criterionToTomlPairs c)))]
  match spec.mode with
  | .workerLoop worker loopConfig =>
    base ++ [
      ("worker", .table (workerConfigToTomlPairs worker)),
      ("maxIterations", .int (Int.ofNat loopConfig.maxIterations)),
      ("stuckThreshold", .int (Int.ofNat loopConfig.stuckThreshold))]
  | .verify => base

-- ============================================================================
-- Layer 2: TomlValue → String (tested, not proven)
-- ============================================================================

/-- Render a TOML value as a string. Strings are quoted, multi-line strings
    (containing newlines) use triple-quote syntax. -/
def renderValue : TomlValue → String
  | .str s =>
    if s.any (· == '\n') then
      "\"\"\"\n" ++ s.foldl (fun acc c =>
        if c == '\\' then acc ++ "\\\\"
        else if c == '"' then acc ++ "\\\""
        else acc.push c) "" ++ "\"\"\""
    else
      "\"" ++ s.foldl (fun acc c =>
        if c == '\\' then acc ++ "\\\\"
        else if c == '"' then acc ++ "\\\""
        else acc.push c) "" ++ "\""
  | .int n => toString n
  | .bool b => if b then "true" else "false"
  | .array items => "[" ++ ", ".intercalate (renderArray items) ++ "]"
  -- Tables are rendered via renderTableSection/renderArrayOfTables, never inline
  | .table _ => ""
where
  renderArray : List TomlValue → List String
    | [] => []
    | item :: rest => renderValue item :: renderArray rest

/-- Render a list of TOML key-value pairs as a TOML document string.
    Handles top-level scalars, `[table]` sections, and `[[array]]` sections. -/
def renderToml (pairs : List (String × TomlValue)) : String :=
  let scalars := pairs.filter fun (_, v) => match v with | .table _ | .array _ => false | _ => true
  let tables := pairs.filter fun (_, v) => match v with | .table _ => true | _ => false
  let arrays := pairs.filter fun (_, v) => match v with | .array _ => true | _ => false
  let scalarText := scalars.foldl (fun acc (k, v) => acc ++ k ++ " = " ++ renderValue v ++ "\n") ""
  let tableText := tables.foldl (fun acc (k, v) =>
    match v with
    | .table inner => acc ++ renderTableSection k inner
    | _ => acc) ""
  let arrayText := arrays.foldl (fun acc (k, v) =>
    match v with
    | .array items => acc ++ renderArrayOfTables k items
    | _ => acc) ""
  scalarText ++ tableText ++ arrayText
where
  renderTableBody (parentKey : String) (inner : List (String × TomlValue)) : String :=
    let scalars := inner.filter fun (_, v) => match v with | .table _ => false | _ => true
    let subTables := inner.filter fun (_, v) => match v with | .table _ => true | _ => false
    let body := scalars.foldl (fun acc (k, v) => acc ++ k ++ " = " ++ renderValue v ++ "\n") ""
    let subBody := subTables.foldl (fun acc (k, v) =>
      match v with
      | .table subInner =>
        acc ++ "\n[" ++ parentKey ++ "." ++ k ++ "]\n" ++
        subInner.foldl (fun acc2 (sk, sv) => acc2 ++ sk ++ " = " ++ renderValue sv ++ "\n") ""
      | _ => acc) ""
    body ++ subBody
  renderTableSection (key : String) (inner : List (String × TomlValue)) : String :=
    "\n[" ++ key ++ "]\n" ++ renderTableBody key inner
  renderArrayOfTables (key : String) (items : List TomlValue) : String :=
    items.foldl (fun acc item =>
      match item with
      | .table inner => acc ++ "\n[[" ++ key ++ "]]\n" ++ renderTableBody key inner
      | _ => acc) ""

/-- Serialize a Spec to a TOML document string.
    Composition: `specToTomlPairs` (proven) then `renderToml` (tested). -/
def specToToml (spec : Spec) : String := renderToml (specToTomlPairs spec)

end Qed.TomlSerializer
