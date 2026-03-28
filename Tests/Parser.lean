import Qed

set_option autoImplicit false

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
  | .error errorInfo =>
    IO.eprintln s!"  parse error: {errorInfo}"
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
  | .error errorInfo =>
    IO.eprintln s!"  parse error: {errorInfo}"
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
  | .error errorInfo =>
    IO.eprintln s!"  parse error: {errorInfo}"
    return false

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
        | .agent _ model _ _ => model == Qed.defaultAgentModel
        | _ => false
    | none => return false
  | .error _ => return false

def testParseJsonDefaultsAgentTimeoutTo600 : IO Bool := do
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
        | .agent _ _ _ timeout => timeout == Qed.defaultAgentTimeout
        | _ => false
    | none => return false
  | .error _ => return false

def testParseJsonDefaultsAgentScheduleToHeavy : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"agent\", \"prompt\": \"check\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    match spec.criteria.head? with
    | some criterion => return criterion.schedule == .heavy
    | none => return false
  | .error _ => return false

def testParseJsonDefaultsHumanScheduleToManual : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"human\", \"instruction\": \"check\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok spec =>
    match spec.criteria.head? with
    | some criterion => return criterion.schedule == Schedule.manual
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
      | .command _ _ _ => "command"
      | .proof _ _ => "proof"
      | .agent _ _ _ _ => "agent"
      | _ => "other"
    return types == ["command", "proof", "agent"]
  | .error errorInfo =>
    IO.eprintln s!"  parse error: {errorInfo}"
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
  | .error errorInfo =>
    IO.eprintln s!"  parse error: {errorInfo}"
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
  | .error errorInfo =>
    IO.eprintln s!"  parse error: {errorInfo}"
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
  | .error errorInfo =>
    IO.eprintln s!"  parse error: {errorInfo}"
    return false

def testParseJsonErrorsOnMissingName : IO Bool := do
  -- Arrange
  let json := "{\"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"echo\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error errorInfo =>
    -- Parser-level errors carry only a message — file/line are added by SpecLoader
    return errorInfo.message.contains "name" &&
      errorInfo.file.isNone && errorInfo.line.isNone

def testParseJsonErrorsOnMissingCriteria : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\"}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error errorInfo =>
    return errorInfo.message.contains "criteria" &&
      errorInfo.file.isNone && errorInfo.hint.isNone

def testParseJsonErrorsOnEmptyCriteriaInVerifyMode : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": []}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error errorInfo => return errorInfo.message.contains "at least one"

def testParseJsonErrorsOnUnknownVerifyType : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"magic\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error errorInfo => return errorInfo.message.contains "magic"

def testParseJsonErrorsOnMissingVerifyField : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\"}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error errorInfo => return errorInfo.message.contains "verify"

def testParseJsonErrorsOnMissingCommandRun : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error errorInfo => return errorInfo.message.contains "run"

def testParseJsonErrorsOnInvalidSchedule : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"t\", \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"echo\"}, \"schedule\": \"nightly\"}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error errorInfo => return errorInfo.message.contains "nightly"

def testParseJsonRejectsMaxIterationsWithoutWorker : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"bad\", \"maxIterations\": 5, \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"echo\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error errorInfo => return errorInfo.message.contains "maxIterations" && errorInfo.message.contains "worker"

def testParseJsonRejectsStuckThresholdWithoutWorker : IO Bool := do
  -- Arrange
  let json := "{\"name\": \"bad\", \"stuckThreshold\": 3, \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"echo\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error errorInfo => return errorInfo.message.contains "stuckThreshold" && errorInfo.message.contains "worker"

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
  | .error errorInfo =>
    IO.eprintln s!"  parse error: {errorInfo}"
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
  | .error errorInfo =>
    IO.eprintln s!"  parse error: {errorInfo}"
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
  | .error errorInfo =>
    IO.eprintln s!"  parse error: {errorInfo}"
    return false

def testParseJsonRejectsWorkerWithoutCommandOrPrompt : IO Bool := do
  -- Arrange: worker with neither command nor prompt
  let json := "{\"name\": \"t\", \"worker\": {\"workdir\": \"src\"}, \"criteria\": [{\"description\": \"d\", \"verify\": {\"type\": \"command\", \"run\": \"echo\"}}]}"
  -- Act
  let result := Parser.parseJson json
  -- Assert
  match result with
  | .ok _ => return false
  | .error errorInfo => return errorInfo.message.contains "command" && errorInfo.message.contains "prompt"

def parserTests : List (String × IO Bool) := [
  ("testParseJsonReturnsVerifyModeWhenNoWorker", testParseJsonReturnsVerifyModeWhenNoWorker),
  ("testParseJsonReturnsWorkerLoopWithDefaults", testParseJsonReturnsWorkerLoopWithDefaults),
  ("testParseJsonAppliesCustomLoopConfig", testParseJsonAppliesCustomLoopConfig),
  ("testParseJsonDefaultsAgentReviewModelToSonnet", testParseJsonDefaultsAgentReviewModelToSonnet),
  ("testParseJsonDefaultsAgentTimeoutTo600", testParseJsonDefaultsAgentTimeoutTo600),
  ("testParseJsonDefaultsAgentScheduleToHeavy", testParseJsonDefaultsAgentScheduleToHeavy),
  ("testParseJsonDefaultsHumanScheduleToManual", testParseJsonDefaultsHumanScheduleToManual),
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
  ("testParseJsonErrorsOnInvalidSchedule", testParseJsonErrorsOnInvalidSchedule),
  ("testParseJsonRejectsMaxIterationsWithoutWorker", testParseJsonRejectsMaxIterationsWithoutWorker),
  ("testParseJsonRejectsStuckThresholdWithoutWorker", testParseJsonRejectsStuckThresholdWithoutWorker),
  ("testParseJsonWorkerWithPromptNoCommand", testParseJsonWorkerWithPromptNoCommand),
  ("testParseJsonWorkerWithCustomModel", testParseJsonWorkerWithCustomModel),
  ("testParseJsonWorkerDefaultsModelToDefault", testParseJsonWorkerDefaultsModelToDefault),
  ("testParseJsonRejectsWorkerWithoutCommandOrPrompt", testParseJsonRejectsWorkerWithoutCommandOrPrompt)
]
