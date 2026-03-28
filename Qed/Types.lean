namespace Qed

/-- Default timeout for command verification (seconds). -/
def defaultCommandTimeout : Nat := 300

/-- Default timeout for property-based testing (seconds). -/
def defaultPropertyTimeout : Nat := 600

/-- Default timeout for agent verification (seconds). -/
def defaultAgentTimeout : Nat := 600

/-- Default timeout for the worker process (seconds). -/
def defaultWorkerTimeout : Nat := 3600

/-- Default model for agent verification. -/
def defaultAgentModel : String := "claude-opus-4-6"

/-- Supported proof systems for proof verification. -/
def supportedProvers : List String := ["lean4"]

/-- Default maximum iterations for the worker loop. -/
def defaultMaxIterations : Nat := 10

/-- Default consecutive failure threshold for stuck detection. -/
def defaultStuckThreshold : Nat := 3

/-- How a single acceptance criterion is verified. -/
inductive VerifyType where
  /-- Run a shell command, check exit code.
      `lock` lists glob patterns whose matched files are hashed into `qed.lock`. -/
  | command (run : String) (timeout : Nat := defaultCommandTimeout) (lock : Option (List String) := none)
  /-- Spawn an independent LLM agent to review the criterion.
      `command` is a shell command that receives the prompt via `$QED_VERIFIER_PROMPT`.
      Defaults to Claude CLI. -/
  | agent (prompt : String) (model : String := defaultAgentModel) (command : Option String := none) (timeout : Nat := defaultAgentTimeout)
  /-- Run property-based tests.
      `lock` lists glob patterns whose matched files are hashed into `qed.lock`. -/
  | property (run : String) (timeout : Nat := defaultPropertyTimeout) (lock : Option (List String) := none)
  /-- Run a formal proof checker. Proof targets are auto-locked (theorem
      statement extraction). -/
  | proof (prover : String) (target : String)
  /-- Ask a human to verify. -/
  | human (instruction : String)
  deriving Repr, BEq

/-- When a criterion runs. Controls which execution contexts include it.
    Forms a hierarchy: always ⊃ heavy ⊃ manual. -/
inductive Schedule where
  /-- Every run — CI, pre-push hooks, explicit invocation. Default for
      automatable types (command, property, proof). -/
  | always
  /-- Resource-heavy — included with `--extended`, excluded by default in
      CI and `--auto`. Default for agent verification. -/
  | heavy
  /-- Only via explicit invocation (`qed verify` / `qed run` without flags).
      For interactive criteria requiring human presence. -/
  | manual
  deriving Repr, BEq

/-- A single acceptance criterion: a description and how to verify it. -/
structure AcceptanceCriterion where
  description : String
  verify : VerifyType
  /-- When this criterion runs. Defaults based on verify type:
      human defaults to `manual` (interactive),
      agent defaults to `heavy` (automated but resource-heavy),
      everything else defaults to `always`. -/
  schedule : Schedule := match verify with
    | .human _ => .manual
    | .agent _ _ _ _ => .heavy
    | _ => .always
  /-- When set, the criterion is intentionally skipped with the given reason.
      Skipped criteria show `[SKIP]` in output and do not affect pass/fail. -/
  skip : Option String := none
  deriving Repr, BEq

/-- Configuration for the worker agent.
    Two tiers of usage:
    - **Tier 1 (prompt present):** agent invocation — qed manages the prompt,
      appends failure feedback on retries, and passes it via `$QED_WORKER_PROMPT`.
      Defaults to Claude CLI if no command specified.
    - **Tier 2 (no prompt):** script worker — qed runs the command as-is with
      env vars (`QED_WORKER_ITERATION`, `QED_WORKER_FAILURES_FILE`) available.
    At least one of `command` or `prompt` must be present (enforced by parser). -/
structure WorkerConfig where
  command : Option String := none
  prompt : Option String := none
  model : String := defaultAgentModel
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

/-- A spec pinned to a specific file state. Carries the file path and a
    SHA-256 hash of the raw file bytes at load time for integrity verification.
    Not serialized — this is runtime-only provenance tracking. -/
structure Spec.Pinned where
  spec : Spec
  path : System.FilePath
  contentHash : String
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

/-- Whether a VerificationResult was skipped. -/
def VerificationResult.isSkipped : VerificationResult → Bool
  | .skipped _ => true
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
  /-- Spec file was tampered with during execution. -/
  | integrityViolation (reason : String)
  deriving Repr, BEq

/-- Whether a LoopState is terminal (no further transitions). -/
def LoopState.isTerminal : LoopState → Bool
  | .passed _ => true
  | .stuck _ _ => true
  | .maxIterationsReached _ => true
  | .escalated _ => true
  | .integrityViolation _ => true
  | _ => false

/-- Structured error with optional location, source context, and hint.
    Used as the error type in `Except ErrorInfo` throughout the codebase.
    Error creation sites populate whatever context is available — parsers
    set line/col, the loader adds the file path, validation errors carry
    just the message. The display layer renders all fields consistently. -/
structure ErrorInfo where
  message : String
  file : Option String := none
  line : Option Nat := none
  column : Option Nat := none
  sourceLineText : Option String := none
  hint : Option String := none
  deriving Repr, BEq, Inhabited

instance : ToString ErrorInfo where
  toString info := info.message

end Qed
