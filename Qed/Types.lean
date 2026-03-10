namespace Qed

/-- Default timeout for command verification (seconds). -/
def defaultCommandTimeout : Nat := 300

/-- Default timeout for property-based testing (seconds). -/
def defaultPropertyTimeout : Nat := 600

/-- Default timeout for the worker process (seconds). -/
def defaultWorkerTimeout : Nat := 3600

/-- Default model for agent verification. -/
def defaultAgentModel : String := "claude-opus-4-6"

/-- Default maximum iterations for the worker loop. -/
def defaultMaxIterations : Nat := 10

/-- Default consecutive failure threshold for stuck detection. -/
def defaultStuckThreshold : Nat := 3

/-- How a single acceptance criterion is verified. -/
inductive VerifyType where
  /-- Run a shell command, check exit code. -/
  | command (run : String) (timeout : Nat := defaultCommandTimeout)
  /-- Spawn an independent LLM agent to review the criterion.
      `command` is a shell command that receives the prompt via `$QED_AGENT_PROMPT`.
      Defaults to `claude -p "$QED_AGENT_PROMPT" --model {model}`. -/
  | agent (prompt : String) (model : String := defaultAgentModel) (command : Option String := none)
  /-- Run property-based tests. -/
  | property (run : String) (timeout : Nat := defaultPropertyTimeout)
  /-- Run a formal proof checker. -/
  | proof (prover : String) (target : String)
  /-- Ask a human to verify. -/
  | human (instruction : String)
  deriving Repr, BEq

/-- When a criterion runs in CI. Controls cost without special-casing
    verification types — the CI runner filters by this field alone. -/
inductive CiSchedule where
  /-- Every CI run (PRs, pushes, merge queue). Default for automatable types. -/
  | always
  /-- Only when the default branch changes (merge or direct push). -/
  | trunk
  /-- Never in CI — only via explicit `qed run`. Default for `human`. -/
  | manual
  deriving Repr, BEq

/-- A single acceptance criterion: a description and how to verify it. -/
structure AcceptanceCriterion where
  description : String
  verify : VerifyType
  /-- When this criterion runs in CI. Defaults based on verify type. -/
  ci : CiSchedule := match verify with
    | .human _ => .manual
    | _ => .always
  deriving Repr, BEq

/-- Configuration for the worker agent.
    Two tiers of usage:
    - **Tier 1 (prompt present):** qed manages the prompt. The command receives
      the full prompt (original + failure feedback) via `$QED_PROMPT` env var,
      and qed runs `{command} "$QED_PROMPT"` through the shell.
    - **Tier 2 (no prompt):** full control. qed runs the command as-is with
      env vars (`QED_ITERATION`, `QED_FAILURES_FILE`) for optional use. -/
structure WorkerConfig where
  command : String
  prompt : Option String := none
  workdir : String := "."
  timeout : Nat := defaultWorkerTimeout
  deriving Repr, BEq

/-- Configuration for the loop controller. -/
structure LoopConfig where
  maxIterations : Nat := defaultMaxIterations
  stuckThreshold : Nat := defaultStuckThreshold
  deriving Repr, BEq

/-- How the spec is executed. Worker loop mode iterates a worker against
    criteria with stuck detection. Verify mode runs criteria once (CI). -/
inductive SpecMode where
  /-- Iterative loop: run worker, verify, feed failures back, repeat. -/
  | workerLoop (worker : WorkerConfig) (loopConfig : LoopConfig)
  /-- Single-pass verification: run each criterion once, report results. -/
  | verify
  deriving Repr, BEq

/-- A complete task specification with typed acceptance criteria. -/
structure Spec where
  name : String
  mode : SpecMode
  criteria : List AcceptanceCriterion
  deriving Repr

/-- The result of verifying a single acceptance criterion. -/
inductive VerificationResult where
  /-- The criterion passed. -/
  | pass (details : String)
  /-- The criterion failed. -/
  | fail (details : String)
  /-- A human needs to verify this criterion. -/
  | needsHuman (instruction : String)
  /-- Verification was skipped. -/
  | skipped (reason : String)
  deriving Repr, BEq

/-- Whether a VerificationResult represents a definitive pass. -/
def VerificationResult.isPassed : VerificationResult → Bool
  | .pass _ => true
  | _ => false

/-- Whether a VerificationResult represents a definitive failure. -/
def VerificationResult.isFailed : VerificationResult → Bool
  | .fail _ => true
  | _ => false

/-- The state of the orchestration loop. -/
inductive LoopState where
  /-- Initial state, ready to start. -/
  | ready
  /-- Worker is running for the given iteration. -/
  | workerRunning (iteration : Nat)
  /-- Verifying acceptance criteria for the given iteration. -/
  | verifying (iteration : Nat)
  /-- All auto-verifiable criteria passed. -/
  | passed (iterations : Nat)
  /-- Same failures persisted for stuckThreshold consecutive iterations. -/
  | stuck (iterations : Nat) (failingCriteria : List String)
  /-- Reached the maximum number of iterations. -/
  | maxIterationsReached (iterations : Nat)
  /-- Escalated due to stuck or max iterations. -/
  | escalated (reason : String)
  deriving Repr, BEq

/-- Whether a LoopState is terminal (no further transitions). -/
def LoopState.isTerminal : LoopState → Bool
  | .passed _ => true
  | .stuck _ _ => true
  | .maxIterationsReached _ => true
  | .escalated _ => true
  | _ => false

end Qed
