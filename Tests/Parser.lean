import Qed

open Qed

def testParseVerifyModeSpec : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"test\", \"criteria\": [{\"description\": \"builds\", \"verify\": {\"type\": \"command\", \"run\": \"make build\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    return spec.name == "test" &&
      spec.mode == SpecMode.verify &&
      spec.criteria.length == 1
  | .error e =>
    IO.eprintln s!"  parse error: {e}"
    return false

def testParseWorkerLoopSpec : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"loop-test\", \"worker\": {\"command\": \"run agent\"}, \"criteria\": [{\"description\": \"passes\", \"verify\": {\"type\": \"command\", \"run\": \"make test\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    return spec.name == "loop-test" &&
      (match spec.mode with
        | .workerLoop worker config =>
          worker.command == "run agent" &&
          config.maxIterations == 10 &&
          config.stuckThreshold == 3
        | .verify => false)
  | .error e =>
    IO.eprintln s!"  parse error: {e}"
    return false

def testParseWorkerLoopCustomConfig : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"custom\", \"worker\": {\"command\": \"agent\", \"workdir\": \"src\", \"timeout\": 1800}, \"maxIterations\": 5, \"stuckThreshold\": 2, \"criteria\": [{\"description\": \"ok\", \"verify\": {\"type\": \"command\", \"run\": \"echo\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    return match spec.mode with
      | .workerLoop worker config =>
        worker.command == "agent" &&
        worker.workdir == "src" &&
        worker.timeout == 1800 &&
        config.maxIterations == 5 &&
        config.stuckThreshold == 2
      | .verify => false
  | .error e =>
    IO.eprintln s!"  parse error: {e}"
    return false

def testParseCommandVerifyType : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"make\", \"timeout\": 60}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    match spec.criteria.head? with
    | some criterion =>
      return match criterion.verify with
        | .command run timeout => run == "make" && timeout == 60
        | _ => false
    | none => return false
  | .error _ => return false

def testParseAgentReviewVerifyType : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"agentReview\", \"prompt\": \"check it\", \"model\": \"claude-opus-4-6\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    match spec.criteria.head? with
    | some criterion =>
      return match criterion.verify with
        | .agentReview prompt model => prompt == "check it" && model == "claude-opus-4-6"
        | _ => false
    | none => return false
  | .error _ => return false

def testParseAgentReviewDefaultModel : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"agentReview\", \"prompt\": \"check\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    match spec.criteria.head? with
    | some criterion =>
      return match criterion.verify with
        | .agentReview _ model => model == "claude-sonnet-4-6"
        | _ => false
    | none => return false
  | .error _ => return false

def testParseProofVerifyType : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"proof\", \"prover\": \"lean4\", \"target\": \"Qed.Proofs.T\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    match spec.criteria.head? with
    | some criterion =>
      return match criterion.verify with
        | .proof prover target => prover == "lean4" && target == "Qed.Proofs.T"
        | _ => false
    | none => return false
  | .error _ => return false

def testParsePropertyVerifyType : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"property\", \"run\": \"hypothesis\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    match spec.criteria.head? with
    | some criterion =>
      return match criterion.verify with
        | .property run timeout => run == "hypothesis" && timeout == 600
        | _ => false
    | none => return false
  | .error _ => return false

def testParseHumanVerifyType : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"human\", \"instruction\": \"look at it\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    match spec.criteria.head? with
    | some criterion =>
      return match criterion.verify with
        | .human instruction => instruction == "look at it"
        | _ => false
    | none => return false
  | .error _ => return false

def testParseCiScheduleOverride : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"echo\"}, \"ci\": \"trunk\"}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    match spec.criteria.head? with
    | some criterion => return criterion.ci == CiSchedule.trunk
    | none => return false
  | .error _ => return false

def testParseHumanDefaultCiIsManual : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"human\", \"instruction\": \"check\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    match spec.criteria.head? with
    | some criterion => return criterion.ci == CiSchedule.manual
    | none => return false
  | .error _ => return false

def testParseErrorMissingName : IO Bool := do
  -- Arrange
  let json := "{\"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"echo\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error e => return e.contains "name"

def testParseErrorMissingCriteria : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\"}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error e => return e.contains "criteria"

def testParseErrorVerifyModeNoCriteria : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": []}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error e => return e.contains "at least one"

def testParseErrorUnknownVerifyType : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"magic\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error e => return e.contains "magic"

def parserTests : List (String × IO Bool) := [
  ("testParseVerifyModeSpec", testParseVerifyModeSpec),
  ("testParseWorkerLoopSpec", testParseWorkerLoopSpec),
  ("testParseWorkerLoopCustomConfig", testParseWorkerLoopCustomConfig),
  ("testParseCommandVerifyType", testParseCommandVerifyType),
  ("testParseAgentReviewVerifyType", testParseAgentReviewVerifyType),
  ("testParseAgentReviewDefaultModel", testParseAgentReviewDefaultModel),
  ("testParseProofVerifyType", testParseProofVerifyType),
  ("testParsePropertyVerifyType", testParsePropertyVerifyType),
  ("testParseHumanVerifyType", testParseHumanVerifyType),
  ("testParseCiScheduleOverride", testParseCiScheduleOverride),
  ("testParseHumanDefaultCiIsManual", testParseHumanDefaultCiIsManual),
  ("testParseErrorMissingName", testParseErrorMissingName),
  ("testParseErrorMissingCriteria", testParseErrorMissingCriteria),
  ("testParseErrorVerifyModeNoCriteria", testParseErrorVerifyModeNoCriteria),
  ("testParseErrorUnknownVerifyType", testParseErrorUnknownVerifyType)
]
