import Lean.Data.Json
import Qed.Types

set_option autoImplicit false

namespace Qed.Parser

open Lean Qed

/-- Helper: get a required string field from a JSON object. -/
def parseRequiredString (json : Json) (field : String) : Except ErrorInfo String :=
  match json.getObjValAs? String field with
  | .ok value => .ok value
  | .error _ => .error { message := s!"missing or invalid field '{field}': expected string" }

/-- Helper: get an optional string field with a default. -/
def parseOptionalString (json : Json) (field : String) (default : String) : String :=
  match json.getObjValAs? String field with
  | .ok value => value
  | .error _ => default

/-- Helper: get an optional natural number field with a default. -/
def parseOptionalNat (json : Json) (field : String) (default : Nat) : Except ErrorInfo Nat :=
  match json.getObjValAs? Nat field with
  | .ok value => .ok value
  | .error _ =>
    -- Field absent → use default; field present but wrong type → error
    match json.getObjVal? field with
    | .error _ => .ok default
    | .ok _ => .error { message := s!"field '{field}': expected non-negative integer" }

/-- Parse a Schedule from a JSON string value. -/
def parseSchedule (value : String) : Except ErrorInfo Schedule :=
  match value with
  | "always" => .ok .always
  | "heavy" => .ok .heavy
  | "manual" => .ok .manual
  | other => .error { message := s!"invalid schedule: '{other}' (expected always, heavy, or manual)" }

/-- Parse a single string item from a JSON array element. Named so the
    roundtrip proof can reference it (inline lambdas are hard to match). -/
def parseStringItem (field : String) (item : Json) : Except ErrorInfo String :=
  match item with
  | Json.str s => .ok s
  | _ => .error { message := s!"field '{field}': expected array of strings" }

/-- Parse an optional list of strings from a JSON array field. -/
def parseOptionalStringList (json : Json) (field : String) : Except ErrorInfo (Option (List String)) :=
  match json.getObjVal? field with
  | .error _ => .ok none
  | .ok (Json.arr items) => do
    let strings ← items.toList.mapM (parseStringItem field)
    .ok (some strings)
  | .ok _ => .error { message := s!"field '{field}': expected array" }

/-- Parse a VerifyType from a JSON object (the "verify" field of a criterion). -/
def parseVerifyType (json : Json) : Except ErrorInfo VerifyType := do
  let typeName ← parseRequiredString json "type"
  match typeName with
  | "command" =>
    let run ← parseRequiredString json "run"
    let timeout ← parseOptionalNat json "timeout" defaultCommandTimeout
    let lock ← parseOptionalStringList json "lock"
    .ok (.command run timeout lock)
  | "agent" =>
    let prompt ← parseRequiredString json "prompt"
    let model := parseOptionalString json "model" defaultAgentModel
    let command := match json.getObjVal? "command" with
      | .ok (Json.str s) => some s
      | _ => none
    let timeout ← parseOptionalNat json "timeout" defaultAgentTimeout
    .ok (.agent prompt model command timeout)
  | "property" =>
    let run ← parseRequiredString json "run"
    let timeout ← parseOptionalNat json "timeout" defaultPropertyTimeout
    let lock ← parseOptionalStringList json "lock"
    .ok (.property run timeout lock)
  | "proof" =>
    let prover ← parseRequiredString json "prover"
    let target ← parseRequiredString json "target"
    .ok (.proof prover target)
  | "human" =>
    let instruction ← parseRequiredString json "instruction"
    .ok (.human instruction)
  | other => .error { message := s!"unknown verify type: '{other}'" }

/-- Parse an AcceptanceCriterion from a JSON object. -/
def parseCriterion (json : Json) : Except ErrorInfo AcceptanceCriterion := do
  let description ← parseRequiredString json "description"
  let verifyJson ← match json.getObjVal? "verify" with
    | .ok value => .ok value
    | .error _ => .error { message := "missing field 'verify'" }
  let verify ← parseVerifyType verifyJson
  let schedule ← match json.getObjValAs? String "schedule" with
    | .ok value => parseSchedule value
    | .error _ =>
      -- Default: manual for human, heavy for agent, always for everything else
      .ok (match verify with
        | .human _ => .manual
        | .agent _ _ _ _ => .heavy
        | _ => .always)
  let skip := match json.getObjValAs? String "skip" with
    | .ok value => some value
    | .error _ => none
  .ok { description, verify, schedule, skip }

/-- Parse a WorkerConfig from a JSON object. Does not validate that at least
    one of command/prompt is present — that check lives in parseFromJson. -/
def parseWorkerConfig (json : Json) : Except ErrorInfo WorkerConfig := do
  let command := match json.getObjValAs? String "command" with
    | .ok value => some value
    | .error _ => none
  let prompt := match json.getObjValAs? String "prompt" with
    | .ok value => some value
    | .error _ => none
  let model := parseOptionalString json "model" defaultAgentModel
  let workdir := parseOptionalString json "workdir" "."
  let timeout ← parseOptionalNat json "timeout" defaultWorkerTimeout
  .ok { command, prompt, model, workdir, timeout }

/-- Parse a Spec from a parsed JSON value. -/
def parseFromJson (json : Json) : Except ErrorInfo Spec := do
  let name ← parseRequiredString json "name"

  -- Parse criteria
  let criteriaArray ← match json.getObjVal? "criteria" with
    | .ok (Json.arr items) => .ok items
    | .ok _ => .error { message := "field 'criteria': expected array" }
    | .error _ => .error { message := "missing field 'criteria'" }
  let criteria ← criteriaArray.toList.mapM parseCriterion

  -- Parse mode: worker present → workerLoop, absent → verify
  let mode ← match json.getObjVal? "worker" with
    | .ok workerJson =>
      let worker ← parseWorkerConfig workerJson
      -- At least one of command or prompt must be present
      if worker.command.isNone && worker.prompt.isNone then
        .error { message := "worker requires at least 'command' or 'prompt'" }
      else
        let maxIterations ← parseOptionalNat json "maxIterations" defaultMaxIterations
        let stuckThreshold ← parseOptionalNat json "stuckThreshold" defaultStuckThreshold
        .ok (SpecMode.workerLoop worker { maxIterations, stuckThreshold })
    | .error _ =>
      -- Verify mode: reject worker loop fields that don't apply
      if (json.getObjVal? "maxIterations").isOk then
        .error { message := "'maxIterations' requires a [worker] section" }
      else if (json.getObjVal? "stuckThreshold").isOk then
        .error { message := "'stuckThreshold' requires a [worker] section" }
      else if criteria.isEmpty then
        .error { message := "verify mode (no worker) requires at least one criterion" }
      else
        .ok SpecMode.verify

  .ok { name, mode, criteria }

/-- Parse a Spec from a JSON string. -/
def parseJson (input : String) : Except ErrorInfo Spec := do
  let json ← (Json.parse input).mapError fun error => ({ message := error } : ErrorInfo)
  parseFromJson json

end Qed.Parser
