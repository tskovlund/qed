import Qed.Types
import Qed.Shell

set_option autoImplicit false

namespace Qed.Agent

open Qed

/-- Environment variable names set by qed for worker processes. -/
def workerPromptVar : String := "QED_WORKER_PROMPT"
def workerIterationVar : String := "QED_WORKER_ITERATION"
def workerFailuresFileVar : String := "QED_WORKER_FAILURES_FILE"

/-- Environment variable names set by qed for verifier agents. -/
def verifierPromptVar : String := "QED_VERIFIER_PROMPT"
def verifierSystemPromptVar : String := "QED_VERIFIER_SYSTEM_PROMPT"

/-- Default command for agent workers (multi-turn work). -/
def defaultWorkerCommand (model : String) : String :=
  s!"claude -p \"${workerPromptVar}\" --model {Shell.shellQuote model}"

/-- Default command for agent verifiers (single-turn review with verdict). -/
def defaultVerifierCommand (model : String) : String :=
  s!"claude -p \"${verifierPromptVar}\" --model {Shell.shellQuote model} --system-prompt \"${verifierSystemPromptVar}\" --output-format text --max-turns 1"

/-- Whether an error indicates the agent command is unavailable
    (not installed, can't be launched, etc.) rather than a genuine failure. -/
def isUnavailable (exitCode : UInt32) (stderr : String) : Bool :=
  stderr.contains "not found" || stderr.contains "No such file" ||
  stderr.contains "cannot be launched" || exitCode == 127

end Qed.Agent
