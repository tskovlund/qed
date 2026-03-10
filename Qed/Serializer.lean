import Lean.Data.Json
import Qed.Types

set_option autoImplicit false

namespace Qed.Serializer

open Lean Qed

/-- Serialize a Schedule to its string representation. -/
def scheduleToString : Schedule → String
  | .always => "always"
  | .local => "local"
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

/-- Serialize an AcceptanceCriterion to JSON. Optional `skip` field is only
    emitted when present. -/
def criterionToJson (criterion : AcceptanceCriterion) : Json :=
  let base := [
    ("description", Json.str criterion.description),
    ("verify", verifyTypeToJson criterion.verify),
    ("schedule", Json.str (scheduleToString criterion.schedule))]
  let fields := match criterion.skip with
    | some reason => base ++ [("skip", Json.str reason)]
    | none => base
  Json.mkObj fields

/-- Serialize a WorkerConfig to JSON. Optional fields (command, prompt) are
    only emitted when present. Model, workdir, and timeout are always emitted
    to simplify roundtrip proofs. -/
def workerConfigToJson (worker : WorkerConfig) : Json :=
  let base := [
    ("model", Json.str worker.model),
    ("workdir", Json.str worker.workdir),
    ("timeout", Lean.toJson worker.timeout)]
  let withCommand := match worker.command with
    | some c => ("command", Json.str c) :: base
    | none => base
  let withPrompt := match worker.prompt with
    | some p => ("prompt", Json.str p) :: withCommand
    | none => withCommand
  Json.mkObj withPrompt

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
