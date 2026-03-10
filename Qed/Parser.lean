import Lean.Data.Json
import Qed.Types

namespace Qed.Parser

open Lean Qed

/-- Helper: get a required string field from a JSON object. -/
def requireString (json : Json) (field : String) : Except String String :=
  match json.getObjValAs? String field with
  | .ok value => .ok value
  | .error _ => .error s!"missing or invalid field '{field}': expected string"

/-- Helper: get an optional string field with a default. -/
def optionalString (json : Json) (field : String) (default : String) : String :=
  match json.getObjValAs? String field with
  | .ok value => value
  | .error _ => default

/-- Helper: get an optional natural number field with a default. -/
def optionalNat (json : Json) (field : String) (default : Nat) : Except String Nat :=
  match json.getObjValAs? Nat field with
  | .ok value => .ok value
  | .error _ =>
    -- Field absent → use default; field present but wrong type → error
    match json.getObjVal? field with
    | .error _ => .ok default
    | .ok _ => .error s!"field '{field}': expected non-negative integer"

/-- Parse a CiSchedule from a JSON string value. -/
def parseCiSchedule (value : String) : Except String CiSchedule :=
  match value with
  | "always" => .ok .always
  | "trunk" => .ok .trunk
  | "manual" => .ok .manual
  | other => .error s!"invalid ci schedule: '{other}' (expected always, trunk, or manual)"

/-- Parse a VerifyType from a JSON object (the "verify" field of a criterion). -/
def parseVerifyType (json : Json) : Except String VerifyType := do
  let typeName ← requireString json "type"
  match typeName with
  | "command" =>
    let run ← requireString json "run"
    let timeout ← optionalNat json "timeout" defaultCommandTimeout
    .ok (.command run timeout)
  | "agent" =>
    let prompt ← requireString json "prompt"
    let model := optionalString json "model" defaultAgentModel
    let command := match json.getObjVal? "command" with
      | .ok (Json.str s) => some s
      | _ => none
    .ok (.agent prompt model command)
  | "property" =>
    let run ← requireString json "run"
    let timeout ← optionalNat json "timeout" defaultPropertyTimeout
    .ok (.property run timeout)
  | "proof" =>
    let prover ← requireString json "prover"
    let target ← requireString json "target"
    .ok (.proof prover target)
  | "human" =>
    let instruction ← requireString json "instruction"
    .ok (.human instruction)
  | other => .error s!"unknown verify type: '{other}'"

/-- Parse an AcceptanceCriterion from a JSON object. -/
def parseCriterion (json : Json) : Except String AcceptanceCriterion := do
  let description ← requireString json "description"
  let verifyJson ← match json.getObjVal? "verify" with
    | .ok value => .ok value
    | .error _ => .error "missing field 'verify'"
  let verify ← parseVerifyType verifyJson
  let ci ← match json.getObjValAs? String "ci" with
    | .ok value => parseCiSchedule value
    | .error _ =>
      -- Default: manual for human, always for everything else
      .ok (match verify with
        | .human _ => .manual
        | _ => .always)
  .ok { description, verify, ci }

/-- Parse a WorkerConfig from a JSON object. Does not validate that at least
    one of command/prompt is present — that check lives in parseFromJson. -/
def parseWorkerConfig (json : Json) : Except String WorkerConfig := do
  let command := match json.getObjValAs? String "command" with
    | .ok value => some value
    | .error _ => none
  let prompt := match json.getObjValAs? String "prompt" with
    | .ok value => some value
    | .error _ => none
  let model := optionalString json "model" defaultAgentModel
  let workdir := optionalString json "workdir" "."
  let timeout ← optionalNat json "timeout" defaultWorkerTimeout
  .ok { command, prompt, model, workdir, timeout }

/-- Parse a Spec from a parsed JSON value. -/
def parseFromJson (json : Json) : Except String Spec := do
  let name ← requireString json "name"

  -- Parse criteria
  let criteriaArray ← match json.getObjVal? "criteria" with
    | .ok (Json.arr items) => .ok items
    | .ok _ => .error "field 'criteria': expected array"
    | .error _ => .error "missing field 'criteria'"
  let criteria ← criteriaArray.toList.mapM parseCriterion

  -- Parse mode: worker present → workerLoop, absent → verify
  let mode ← match json.getObjVal? "worker" with
    | .ok workerJson =>
      let worker ← parseWorkerConfig workerJson
      -- At least one of command or prompt must be present
      if worker.command.isNone && worker.prompt.isNone then
        .error "worker requires at least 'command' or 'prompt'"
      else
        let maxIterations ← optionalNat json "maxIterations" defaultMaxIterations
        let stuckThreshold ← optionalNat json "stuckThreshold" defaultStuckThreshold
        .ok (SpecMode.workerLoop worker { maxIterations, stuckThreshold })
    | .error _ =>
      -- Verify mode: reject worker loop fields that don't apply
      if (json.getObjVal? "maxIterations").isOk then
        .error "'maxIterations' requires a [worker] section"
      else if (json.getObjVal? "stuckThreshold").isOk then
        .error "'stuckThreshold' requires a [worker] section"
      else if criteria.isEmpty then
        .error "verify mode (no worker) requires at least one criterion"
      else
        .ok SpecMode.verify

  .ok { name, mode, criteria }

/-- Parse a Spec from a JSON string. -/
def parseJson (input : String) : Except String Spec := do
  let json ← Json.parse input
  parseFromJson json

end Qed.Parser
