import Lean.Data.Json
import Qed.Types

set_option autoImplicit false

namespace Qed.Serializer

open Lean Qed

/-- Serialize a CiSchedule to its string representation. -/
def ciScheduleToString : CiSchedule → String
  | .always => "always"
  | .trunk => "trunk"
  | .manual => "manual"

/-- Serialize a VerifyType to JSON. -/
def verifyTypeToJson : VerifyType → Json
  | .command run timeout => Json.mkObj [
      ("type", Json.str "command"),
      ("run", Json.str run),
      ("timeout", Lean.toJson timeout)]
  | .agent prompt model command => Json.mkObj <|
      [("type", Json.str "agent"),
       ("prompt", Json.str prompt),
       ("model", Json.str model)] ++
      match command with
      | some cmd => [("command", Json.str cmd)]
      | none => []
  | .property run timeout => Json.mkObj [
      ("type", Json.str "property"),
      ("run", Json.str run),
      ("timeout", Lean.toJson timeout)]
  | .proof prover target => Json.mkObj [
      ("type", Json.str "proof"),
      ("prover", Json.str prover),
      ("target", Json.str target)]
  | .human instruction => Json.mkObj [
      ("type", Json.str "human"),
      ("instruction", Json.str instruction)]

/-- Serialize an AcceptanceCriterion to JSON. -/
def criterionToJson (criterion : AcceptanceCriterion) : Json := Json.mkObj [
  ("description", Json.str criterion.description),
  ("verify", verifyTypeToJson criterion.verify),
  ("ci", Json.str (ciScheduleToString criterion.ci))]

/-- Serialize a WorkerConfig to JSON. Prompt is only emitted when present. -/
def workerConfigToJson (worker : WorkerConfig) : Json :=
  let base := [
    ("command", Json.str worker.command),
    ("workdir", Json.str worker.workdir),
    ("timeout", Lean.toJson worker.timeout)]
  match worker.prompt with
  | some p => Json.mkObj (("prompt", Json.str p) :: base)
  | none => Json.mkObj base

/-- Serialize a Spec to JSON. All fields are always emitted (including defaults)
to simplify roundtrip proofs. -/
def specToJson (spec : Spec) : Json :=
  let base := [
    ("name", Json.str spec.name),
    ("criteria", Json.arr (spec.criteria.map criterionToJson).toArray)]
  let fields := match spec.mode with
    | .workerLoop worker loopConfig =>
      base ++ [
        ("worker", workerConfigToJson worker),
        ("maxIterations", Lean.toJson loopConfig.maxIterations),
        ("stuckThreshold", Lean.toJson loopConfig.stuckThreshold)]
    | .verify => base
  Json.mkObj fields

/-- Serialize a Spec to a JSON string. -/
def serialize (spec : Spec) : String :=
  (specToJson spec).pretty

end Qed.Serializer
