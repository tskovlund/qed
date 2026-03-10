import Qed

open Qed

def testParseJsonReturnsVerifyModeWhenNoWorker : IO Bool := do
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

def testParseJsonReturnsWorkerLoopWithDefaults : IO Bool := do
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
          worker.command == some "run agent" &&
          config.maxIterations == 10 &&
          config.stuckThreshold == 3
        | .verify => false)
  | .error e =>
    IO.eprintln s!"  parse error: {e}"
    return false

def testParseJsonAppliesCustomLoopConfig : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"custom\", \"worker\": {\"command\": \"agent\", \"workdir\": \"src\", \"timeout\": 1800}, \"maxIterations\": 5, \"stuckThreshold\": 2, \"criteria\": [{\"description\": \"ok\", \"verify\": {\"type\": \"command\", \"run\": \"echo\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    return match spec.mode with
      | .workerLoop worker config =>
        worker.command == some "agent" &&
        worker.workdir == "src" &&
        worker.timeout == 1800 &&
        config.maxIterations == 5 &&
        config.stuckThreshold == 2
      | .verify => false
  | .error e =>
    IO.eprintln s!"  parse error: {e}"
    return false

def testParseJsonExtractsCommandFields : IO Bool := do
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

def testParseJsonExtractsAgentReviewFields : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"agent\", \"prompt\": \"check it\", \"model\": \"claude-opus-4-6\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    match spec.criteria.head? with
    | some criterion =>
      return match criterion.verify with
        | .agent prompt model => prompt == "check it" && model == "claude-opus-4-6"
        | _ => false
    | none => return false
  | .error _ => return false

def testParseJsonExtractsAgentCustomCommand : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"agent\", \"prompt\": \"check it\", \"command\": \"ollama run llama3\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    match spec.criteria.head? with
    | some criterion =>
      return match criterion.verify with
        | .agent prompt _ command => prompt == "check it" && command == some "ollama run llama3"
        | _ => false
    | none => return false
  | .error _ => return false

def testParseJsonDefaultsAgentCommandToNone : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"agent\", \"prompt\": \"check\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    match spec.criteria.head? with
    | some criterion =>
      return match criterion.verify with
        | .agent _ _ command => command == none
        | _ => false
    | none => return false
  | .error _ => return false

def testParseJsonDefaultsAgentReviewModelToSonnet : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"agent\", \"prompt\": \"check\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    match spec.criteria.head? with
    | some criterion =>
      return match criterion.verify with
        | .agent _ model => model == Qed.defaultAgentModel
        | _ => false
    | none => return false
  | .error _ => return false

def testParseJsonExtractsProofFields : IO Bool := do
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

def testParseJsonExtractsPropertyFieldsWithDefault : IO Bool := do
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

def testParseJsonExtractsHumanInstruction : IO Bool := do
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

def testParseJsonAppliesCiScheduleOverride : IO Bool := do
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

def testParseJsonDefaultsHumanCiToManual : IO Bool := do
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

def testParseJsonPreservesMultipleCriteria : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"multi\", \"criteria\": [{\"description\": \"builds\", \"verify\": {\"type\": \"command\", \"run\": \"make\"}}, {\"description\": \"proven\", \"verify\": {\"type\": \"proof\", \"prover\": \"lean4\", \"target\": \"T\"}}, {\"description\": \"reviewed\", \"verify\": {\"type\": \"agent\", \"prompt\": \"check\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    if spec.criteria.length != 3 then return false
    let types := spec.criteria.map fun c => match c.verify with
      | .command _ _ => "command"
      | .proof _ _ => "proof"
      | .agent _ _ => "agent"
      | _ => "other"
    return types == ["command", "proof", "agent"]
  | .error e =>
    IO.eprintln s!"  parse error: {e}"
    return false

def testParseJsonAllowsEmptyCriteriaInWorkerLoop : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"no-criteria\", \"worker\": {\"command\": \"agent\"}, \"criteria\": []}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    return spec.criteria.isEmpty &&
      (match spec.mode with
        | .workerLoop _ _ => true
        | .verify => false)
  | .error e =>
    IO.eprintln s!"  parse error: {e}"
    return false

def testParseJsonWorkerWithPrompt : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"worker\": {\"command\": \"claude -p\", \"prompt\": \"Implement feature X\"}, \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"echo\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    return match spec.mode with
      | .workerLoop worker _ =>
        worker.command == some "claude -p" &&
        worker.prompt == some "Implement feature X"
      | .verify => false
  | .error e =>
    IO.eprintln s!"  parse error: {e}"
    return false

def testParseJsonWorkerWithoutPrompt : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"worker\": {\"command\": \"./run.sh\"}, \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"echo\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    return match spec.mode with
      | .workerLoop worker _ =>
        worker.command == some "./run.sh" &&
        worker.prompt == none
      | .verify => false
  | .error e =>
    IO.eprintln s!"  parse error: {e}"
    return false

def testParseJsonErrorsOnMissingName : IO Bool := do
  -- Arrange
  let json := "{\"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"echo\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error e => return e.contains "name"

def testParseJsonErrorsOnMissingCriteria : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\"}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error e => return e.contains "criteria"

def testParseJsonErrorsOnEmptyCriteriaInVerifyMode : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": []}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error e => return e.contains "at least one"

def testParseJsonErrorsOnUnknownVerifyType : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"magic\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error e => return e.contains "magic"

def testParseJsonErrorsOnMissingVerifyField : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\"}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error e => return e.contains "verify"

def testParseJsonErrorsOnMissingCommandRun : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error e => return e.contains "run"

def testParseJsonErrorsOnInvalidCiSchedule : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"echo\"}, \"ci\": \"nightly\"}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error e => return e.contains "nightly"

def testParseJsonRejectsMaxIterationsWithoutWorker : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"bad\", \"maxIterations\": 5, \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"echo\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error e => return e.contains "maxIterations" && e.contains "worker"

def testParseJsonRejectsStuckThresholdWithoutWorker : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"bad\", \"stuckThreshold\": 3, \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"echo\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error e => return e.contains "stuckThreshold" && e.contains "worker"

def testParseJsonWorkerWithPromptNoCommand : IO Bool := do
  -- Arrange: agent worker with prompt, no command (defaults to Claude CLI)
  let json := "{\"name\": \"t\", \"worker\": {\"prompt\": \"Do the thing\"}, \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"echo\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    return match spec.mode with
      | .workerLoop worker _ =>
        worker.command == none &&
        worker.prompt == some "Do the thing" &&
        worker.model == Qed.defaultAgentModel
      | .verify => false
  | .error e =>
    IO.eprintln s!"  parse error: {e}"
    return false

def testParseJsonWorkerWithCustomModel : IO Bool := do
  -- Arrange: agent worker with custom model
  let json := "{\"name\": \"t\", \"worker\": {\"prompt\": \"Do the thing\", \"model\": \"claude-sonnet-4-6\"}, \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"echo\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    return match spec.mode with
      | .workerLoop worker _ =>
        worker.model == "claude-sonnet-4-6" &&
        worker.prompt == some "Do the thing"
      | .verify => false
  | .error e =>
    IO.eprintln s!"  parse error: {e}"
    return false

def testParseJsonWorkerDefaultsModelToDefault : IO Bool := do
  -- Arrange: worker without explicit model
  let json := "{\"name\": \"t\", \"worker\": {\"command\": \"run\"}, \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"echo\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    return match spec.mode with
      | .workerLoop worker _ => worker.model == Qed.defaultAgentModel
      | .verify => false
  | .error e =>
    IO.eprintln s!"  parse error: {e}"
    return false

def testParseJsonRejectsWorkerWithoutCommandOrPrompt : IO Bool := do
  -- Arrange: worker with neither command nor prompt
  let json := "{\"name\": \"t\", \"worker\": {\"workdir\": \"src\"}, \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"echo\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error e => return e.contains "command" && e.contains "prompt"

def testParseJsonExtractsSkipReason : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"echo\"}, \"skip\": \"not yet implemented\"}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    match spec.criteria.head? with
    | some criterion => return criterion.skip == some "not yet implemented"
    | none => return false
  | .error _ => return false

def testParseJsonDefaultsSkipToNone : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"echo\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    match spec.criteria.head? with
    | some criterion => return criterion.skip == none
    | none => return false
  | .error _ => return false

def parserTests : List (String × IO Bool) := [
  ("testParseJsonReturnsVerifyModeWhenNoWorker", testParseJsonReturnsVerifyModeWhenNoWorker),
  ("testParseJsonReturnsWorkerLoopWithDefaults", testParseJsonReturnsWorkerLoopWithDefaults),
  ("testParseJsonAppliesCustomLoopConfig", testParseJsonAppliesCustomLoopConfig),
  ("testParseJsonExtractsCommandFields", testParseJsonExtractsCommandFields),
  ("testParseJsonExtractsAgentReviewFields", testParseJsonExtractsAgentReviewFields),
  ("testParseJsonExtractsAgentCustomCommand", testParseJsonExtractsAgentCustomCommand),
  ("testParseJsonDefaultsAgentCommandToNone", testParseJsonDefaultsAgentCommandToNone),
  ("testParseJsonDefaultsAgentReviewModelToSonnet", testParseJsonDefaultsAgentReviewModelToSonnet),
  ("testParseJsonExtractsProofFields", testParseJsonExtractsProofFields),
  ("testParseJsonExtractsPropertyFieldsWithDefault", testParseJsonExtractsPropertyFieldsWithDefault),
  ("testParseJsonExtractsHumanInstruction", testParseJsonExtractsHumanInstruction),
  ("testParseJsonAppliesCiScheduleOverride", testParseJsonAppliesCiScheduleOverride),
  ("testParseJsonDefaultsHumanCiToManual", testParseJsonDefaultsHumanCiToManual),
  ("testParseJsonPreservesMultipleCriteria", testParseJsonPreservesMultipleCriteria),
  ("testParseJsonAllowsEmptyCriteriaInWorkerLoop", testParseJsonAllowsEmptyCriteriaInWorkerLoop),
  ("testParseJsonWorkerWithPrompt", testParseJsonWorkerWithPrompt),
  ("testParseJsonWorkerWithoutPrompt", testParseJsonWorkerWithoutPrompt),
  ("testParseJsonErrorsOnMissingName", testParseJsonErrorsOnMissingName),
  ("testParseJsonErrorsOnMissingCriteria", testParseJsonErrorsOnMissingCriteria),
  ("testParseJsonErrorsOnEmptyCriteriaInVerifyMode", testParseJsonErrorsOnEmptyCriteriaInVerifyMode),
  ("testParseJsonErrorsOnUnknownVerifyType", testParseJsonErrorsOnUnknownVerifyType),
  ("testParseJsonErrorsOnMissingVerifyField", testParseJsonErrorsOnMissingVerifyField),
  ("testParseJsonErrorsOnMissingCommandRun", testParseJsonErrorsOnMissingCommandRun),
  ("testParseJsonErrorsOnInvalidCiSchedule", testParseJsonErrorsOnInvalidCiSchedule),
  ("testParseJsonRejectsMaxIterationsWithoutWorker", testParseJsonRejectsMaxIterationsWithoutWorker),
  ("testParseJsonRejectsStuckThresholdWithoutWorker", testParseJsonRejectsStuckThresholdWithoutWorker),
  ("testParseJsonWorkerWithPromptNoCommand", testParseJsonWorkerWithPromptNoCommand),
  ("testParseJsonWorkerWithCustomModel", testParseJsonWorkerWithCustomModel),
  ("testParseJsonWorkerDefaultsModelToDefault", testParseJsonWorkerDefaultsModelToDefault),
  ("testParseJsonRejectsWorkerWithoutCommandOrPrompt", testParseJsonRejectsWorkerWithoutCommandOrPrompt),
  ("testParseJsonExtractsSkipReason", testParseJsonExtractsSkipReason),
  ("testParseJsonDefaultsSkipToNone", testParseJsonDefaultsSkipToNone)
]
