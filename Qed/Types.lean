namespace Qed

/-- How a single acceptance criterion is verified. -/
inductive VerifyType where
  /-- Run a shell command, check exit code. -/
  | command (run : String) (timeout : Nat := 300)
  /-- Spawn an independent LLM agent to review the diff. -/
  | agentReview (prompt : String) (model : String := "claude-sonnet-4-6")
  /-- Run property-based tests. -/
  | property (run : String) (timeout : Nat := 600)
  /-- Run a formal proof checker. -/
  | proof (prover : String) (target : String)
  /-- Ask a human to verify. -/
  | human (instruction : String)
  deriving Repr, BEq

/-- A single acceptance criterion: a description and how to verify it. -/
structure AcceptanceCriterion where
  description : String
  verify : VerifyType
  deriving Repr, BEq

/-- Configuration for the worker agent. -/
structure WorkerConfig where
  command : String
  workdir : String := "."
  timeout : Nat := 3600
  deriving Repr, BEq

/-- A complete task specification with typed acceptance criteria. -/
structure Spec where
  name : String
  worker : WorkerConfig
  criteria : List AcceptanceCriterion
  maxIterations : Nat := 10
  stuckThreshold : Nat := 3
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

/-- Configuration for the loop controller. -/
structure LoopConfig where
  maxIterations : Nat
  stuckThreshold : Nat
  deriving Repr, BEq

end Qed
