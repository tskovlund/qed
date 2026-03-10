import Qed.Types

open Qed

/-! # JSON Schema generation from Lean types

Exhaustive pattern matches ensure this file won't compile if types
change — the schema can't drift from the source of truth.
-/

namespace DocGen.Schema

-- Exhaustive match on VerifyType — compile error if constructors change
def verifyTypeConstructors : List String :=
  let _ : VerifyType → Unit := fun
    | .command _ _ => ()
    | .agent _ _ _ => ()
    | .property _ _ => ()
    | .proof _ _ => ()
    | .human _ => ()
  ["command", "agent", "property", "proof", "human"]

-- Exhaustive match on CiSchedule — compile error if constructors change
def ciScheduleValues : List String :=
  let _ : CiSchedule → Unit := fun
    | .always => ()
    | .trunk => ()
    | .manual => ()
  ["always", "trunk", "manual"]

-- Exhaustive match on SpecMode — compile error if constructors change
def specModeValues : List String :=
  let _ : SpecMode → Unit := fun
    | .workerLoop _ _ => ()
    | .verify => ()
  ["workerLoop", "verify"]

-- Exhaustive match on VerificationResult — compile error if constructors change
def verificationResultValues : List String :=
  let _ : VerificationResult → Unit := fun
    | .pass _ => ()
    | .fail _ => ()
    | .needsHuman _ => ()
    | .skipped _ => ()
  ["pass", "fail", "needsHuman", "skipped"]

-- Exhaustive match on LoopState — compile error if constructors change
def loopStateValues : List String :=
  let _ : LoopState → Unit := fun
    | .ready => ()
    | .workerRunning _ => ()
    | .verifying _ => ()
    | .passed _ => ()
    | .stuck _ _ => ()
    | .maxIterationsReached _ => ()
    | .escalated _ => ()
  ["ready", "workerRunning", "verifying", "passed", "stuck",
   "maxIterationsReached", "escalated"]

/-- Generate JSON Schema from Lean types. All defaults are extracted from
    actual type constructors — if a default changes, the schema updates. -/
def generate : String :=
  let verifyTypes := verifyTypeConstructors
  let ciSchedules := ciScheduleValues
  let loopConfig : LoopConfig := {}
  let worker : WorkerConfig := { command := some "echo hi" }
s!"\{
  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",
  \"$id\": \"https://qed.skovlund.dev/spec.schema.json\",
  \"title\": \"qed spec\",
  \"description\": \"Typed spec-driven development — acceptance criteria with deterministic verification.\",
  \"type\": \"object\",
  \"required\": [\"name\", \"criteria\"],
  \"additionalProperties\": false,
  \"properties\": \{
    \"name\": \{
      \"type\": \"string\",
      \"description\": \"Unique identifier for this spec.\"
    },
    \"worker\": \{
      \"type\": \"object\",
      \"description\": \"Configuration for the worker. If present, qed runs in worker loop mode (iterate until criteria pass). If absent, qed runs in verify mode (single-pass verification). At least one of 'command' or 'prompt' is required.\",
      \"additionalProperties\": false,
      \"anyOf\": [
        \{\"required\": [\"command\"]},
        \{\"required\": [\"prompt\"]}
      ],
      \"properties\": \{
        \"command\": \{
          \"type\": \"string\",
          \"description\": \"Shell command to run the worker. For agent workers (prompt present), defaults to Claude CLI. For script workers (no prompt), required. The command receives the prompt via $QED_WORKER_PROMPT env var.\"
        },
        \"prompt\": \{
          \"type\": \"string\",
          \"description\": \"Prompt for the worker agent. When present, this is agent invocation — qed manages the prompt (appends failure feedback on retries) and passes it via $QED_WORKER_PROMPT env var. When absent, the command has full control (script worker).\"
        },
        \"model\": \{
          \"type\": \"string\",
          \"description\": \"Model to use for agent workers. Only used when prompt is present.\",
          \"default\": \"{defaultAgentModel}\"
        },
        \"workdir\": \{
          \"type\": \"string\",
          \"description\": \"Working directory for the worker.\",
          \"default\": \"{worker.workdir}\"
        },
        \"timeout\": \{
          \"type\": \"integer\",
          \"description\": \"Worker timeout in seconds.\",
          \"default\": {worker.timeout},
          \"minimum\": 1
        }
      }
    },
    \"criteria\": \{
      \"type\": \"array\",
      \"description\": \"Acceptance criteria — each verified independently.\",
      \"items\": \{
        \"type\": \"object\",
        \"required\": [\"description\", \"verify\"],
        \"additionalProperties\": false,
        \"properties\": \{
          \"description\": \{
            \"type\": \"string\",
            \"description\": \"Human-readable description of what this criterion verifies.\"
          },
          \"verify\": \{
            \"description\": \"How to verify this criterion. Discriminated by the 'type' field.\",
            \"oneOf\": [
              \{
                \"type\": \"object\",
                \"description\": \"Run a shell command and check the exit code.\",
                \"required\": [\"type\", \"run\"],
                \"additionalProperties\": false,
                \"properties\": \{
                  \"type\": \{ \"const\": \"{verifyTypes[0]!}\" },
                  \"run\": \{ \"type\": \"string\", \"description\": \"Shell command to execute.\" },
                  \"timeout\": \{ \"type\": \"integer\", \"default\": {defaultCommandTimeout}, \"minimum\": 1, \"description\": \"Timeout in seconds.\" }
                }
              },
              \{
                \"type\": \"object\",
                \"description\": \"Spawn an independent LLM agent to review against a prompt.\",
                \"required\": [\"type\", \"prompt\"],
                \"additionalProperties\": false,
                \"properties\": \{
                  \"type\": \{ \"const\": \"{verifyTypes[1]!}\" },
                  \"prompt\": \{ \"type\": \"string\", \"description\": \"Review prompt for the agent.\" },
                  \"model\": \{ \"type\": \"string\", \"default\": \"{defaultAgentModel}\", \"description\": \"Model to use for the review.\" },
                  \"command\": \{ \"type\": \"string\", \"description\": \"Shell command to invoke the agent. Receives prompt via $QED_VERIFIER_PROMPT. Defaults to Claude CLI.\" }
                }
              },
              \{
                \"type\": \"object\",
                \"description\": \"Run property-based tests.\",
                \"required\": [\"type\", \"run\"],
                \"additionalProperties\": false,
                \"properties\": \{
                  \"type\": \{ \"const\": \"{verifyTypes[2]!}\" },
                  \"run\": \{ \"type\": \"string\", \"description\": \"Shell command to run property tests.\" },
                  \"timeout\": \{ \"type\": \"integer\", \"default\": {defaultPropertyTimeout}, \"minimum\": 1, \"description\": \"Timeout in seconds.\" }
                }
              },
              \{
                \"type\": \"object\",
                \"description\": \"Verify a formal proof target.\",
                \"required\": [\"type\", \"prover\", \"target\"],
                \"additionalProperties\": false,
                \"properties\": \{
                  \"type\": \{ \"const\": \"{verifyTypes[3]!}\" },
                  \"prover\": \{ \"type\": \"string\", \"description\": \"Proof system (e.g. lean4, coq, agda).\" },
                  \"target\": \{ \"type\": \"string\", \"description\": \"Fully qualified name of the theorem to verify.\" }
                }
              },
              \{
                \"type\": \"object\",
                \"description\": \"Ask a human to verify. Cannot run in CI (ci defaults to 'manual').\",
                \"required\": [\"type\", \"instruction\"],
                \"additionalProperties\": false,
                \"properties\": \{
                  \"type\": \{ \"const\": \"{verifyTypes[4]!}\" },
                  \"instruction\": \{ \"type\": \"string\", \"description\": \"What the human should verify.\" }
                }
              }
            ]
          },
          \"ci\": \{
            \"type\": \"string\",
            \"description\": \"When this criterion runs in CI. Defaults: 'always' for automatable types, 'manual' for human.\",
            \"enum\": [\"{ciSchedules[0]!}\", \"{ciSchedules[1]!}\", \"{ciSchedules[2]!}\"],
            \"default\": \"always\"
          }
        }
      }
    },
    \"maxIterations\": \{
      \"type\": \"integer\",
      \"description\": \"Maximum worker iterations before giving up. Only valid when worker is present.\",
      \"default\": {loopConfig.maxIterations},
      \"minimum\": 1
    },
    \"stuckThreshold\": \{
      \"type\": \"integer\",
      \"description\": \"Consecutive identical failures before declaring stuck. Only valid when worker is present.\",
      \"default\": {loopConfig.stuckThreshold},
      \"minimum\": 1
    }
  },
  \"if\": \{
    \"required\": [\"worker\"]
  },
  \"then\": \{
    \"description\": \"Worker loop mode: worker iterates against criteria.\"
  },
  \"else\": \{
    \"description\": \"Verify mode: single-pass verification, criteria required.\",
    \"properties\": \{
      \"criteria\": \{ \"minItems\": 1 }
    },
    \"not\": \{
      \"required\": [\"maxIterations\"]
    }
  }
}"

end DocGen.Schema
