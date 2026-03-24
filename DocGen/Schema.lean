import Qed.Types

open Qed

/-! # JSON Schema generation from Lean types

Exhaustive pattern matches ensure this file won't compile if types
change — the schema can't drift from the source of truth.

The schema is constructed as an ordered JSON value tree and rendered
with a width-aware pretty printer matching prettier's formatting.
-/

namespace DocGen.Schema

-- Exhaustive match on VerifyType — compile error if constructors change
def verifyTypeConstructors : List String :=
  let _ : VerifyType → Unit := fun
    | .command _ _ _ => ()
    | .agent _ _ _ _ => ()
    | .property _ _ _ => ()
    | .proof _ _ => ()
    | .human _ => ()
  ["command", "agent", "property", "proof", "human"]

-- Exhaustive match on Schedule — compile error if constructors change
def scheduleValues : List String :=
  let _ : Schedule → Unit := fun
    | .always => ()
    | .heavy => ()
    | .manual => ()
  ["always", "heavy", "manual"]

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
    | .integrityViolation _ => ()
  ["ready", "workerRunning", "verifying", "passed", "stuck",
   "maxIterationsReached", "escalated", "integrityViolation"]

/-- Ordered JSON value type. Unlike `Lean.Json`, objects preserve field order. -/
inductive JsonValue where
  | null
  | bool (value : Bool)
  | num (value : Int)
  | str (value : String)
  | arr (items : List JsonValue)
  | obj (fields : List (String × JsonValue))

namespace JsonValue

private def escapeJsonString (s : String) : String :=
  String.join (s.toList.map fun c => match c with
    | '"' => "\\\""
    | '\\' => "\\\\"
    | '\n' => "\\n"
    | '\r' => "\\r"
    | '\t' => "\\t"
    | c => String.singleton c)

/-- Render on a single line (no newlines). -/
partial def flatRender : JsonValue → String
  | .null => "null"
  | .bool b => if b then "true" else "false"
  | .num n => toString n
  | .str s => "\"" ++ escapeJsonString s ++ "\""
  | .arr [] => "[]"
  | .arr items => "[" ++ ", ".intercalate (items.map flatRender) ++ "]"
  | .obj [] => "{}"
  | .obj fields =>
    "{ " ++ ", ".intercalate (fields.map fun (k, v) =>
      "\"" ++ escapeJsonString k ++ "\": " ++ flatRender v) ++ " }"

private def printWidth : Nat := 80

private def indentString (level : Nat) : String :=
  String.ofList (List.replicate (level * 2) ' ')

/-- Width-aware renderer matching prettier's JSON formatting.
    Collapses objects and arrays to a single line when they fit
    within the print width at the current column position. -/
partial def render (value : JsonValue) (indent : Nat := 0) (column : Nat := 0) : String :=
  let flat := flatRender value
  if column + flat.length ≤ printWidth then flat
  else
    let childIndent := indent + 1
    let childIndentStr := indentString childIndent
    let indentStr := indentString indent
    match value with
    | .arr items =>
      let rendered := items.map fun item =>
        childIndentStr ++ render item childIndent (childIndent * 2)
      "[\n" ++ ",\n".intercalate rendered ++ "\n" ++ indentStr ++ "]"
    | .obj fields =>
      let rendered := fields.map fun (k, v) =>
        let keyPart := "\"" ++ escapeJsonString k ++ "\": "
        let valueColumn := childIndent * 2 + keyPart.length
        childIndentStr ++ keyPart ++ render v childIndent valueColumn
      "{\n" ++ ",\n".intercalate rendered ++ "\n" ++ indentStr ++ "}"
    | _ => flat

end JsonValue

-- Construction helpers
private def str (s : String) : JsonValue := .str s
private def num (n : Nat) : JsonValue := .num (Int.ofNat n)
private def bool (b : Bool) : JsonValue := .bool b
private def arr (items : List JsonValue) : JsonValue := .arr items
private def obj (fields : List (String × JsonValue)) : JsonValue := .obj fields

/-- Generate JSON Schema from Lean types. All defaults are extracted from
    actual type constructors — if a default changes, the schema updates. -/
def generate : String :=
  let verifyTypes := verifyTypeConstructors
  let schedules := scheduleValues
  let loopConfig : LoopConfig := {}
  let worker : WorkerConfig := { command := some "echo hi" }
  let schema := obj [
    ("$schema", str "https://json-schema.org/draft/2020-12/schema"),
    ("$id", str "https://qed.skovlund.dev/spec.schema.json"),
    ("title", str "qed spec"),
    ("description", str "Typed spec-driven development — acceptance criteria with deterministic verification."),
    ("type", str "object"),
    ("required", arr [str "name", str "criteria"]),
    ("additionalProperties", bool false),
    ("properties", obj [
      ("name", obj [
        ("type", str "string"),
        ("description", str "Unique identifier for this spec.")
      ]),
      ("worker", obj [
        ("type", str "object"),
        ("description", str "Configuration for the worker. If present, qed runs in worker loop mode (iterate until criteria pass). If absent, qed runs in verify mode (single-pass verification). At least one of 'command' or 'prompt' is required."),
        ("additionalProperties", bool false),
        ("anyOf", arr [
          obj [("required", arr [str "command"])],
          obj [("required", arr [str "prompt"])]
        ]),
        ("properties", obj [
          ("command", obj [
            ("type", str "string"),
            ("description", str "Shell command to run the worker. For agent workers (prompt present), defaults to Claude CLI. For script workers (no prompt), required. The command receives the prompt via $QED_WORKER_PROMPT env var.")
          ]),
          ("prompt", obj [
            ("type", str "string"),
            ("description", str "Prompt for the worker agent. When present, this is agent invocation — qed manages the prompt (appends failure feedback on retries) and passes it via $QED_WORKER_PROMPT env var. When absent, the command has full control (script worker).")
          ]),
          ("model", obj [
            ("type", str "string"),
            ("description", str "Model to use for agent workers. Only used when prompt is present."),
            ("default", str defaultAgentModel)
          ]),
          ("workdir", obj [
            ("type", str "string"),
            ("description", str "Working directory for the worker."),
            ("default", str worker.workdir)
          ]),
          ("timeout", obj [
            ("type", str "integer"),
            ("description", str "Worker timeout in seconds."),
            ("default", num worker.timeout),
            ("minimum", num 1)
          ])
        ])
      ]),
      ("criteria", obj [
        ("type", str "array"),
        ("description", str "Acceptance criteria — each verified independently."),
        ("items", obj [
          ("type", str "object"),
          ("required", arr [str "description", str "verify"]),
          ("additionalProperties", bool false),
          ("properties", obj [
            ("description", obj [
              ("type", str "string"),
              ("description", str "Human-readable description of what this criterion verifies.")
            ]),
            ("verify", obj [
              ("description", str "How to verify this criterion. Discriminated by the 'type' field."),
              ("oneOf", arr [
                obj [
                  ("type", str "object"),
                  ("description", str "Run a shell command and check the exit code."),
                  ("required", arr [str "type", str "run"]),
                  ("additionalProperties", bool false),
                  ("properties", obj [
                    ("type", obj [("const", str verifyTypes[0]!)]),
                    ("run", obj [
                      ("type", str "string"),
                      ("description", str "Shell command to execute.")
                    ]),
                    ("timeout", obj [
                      ("type", str "integer"),
                      ("default", num defaultCommandTimeout),
                      ("minimum", num 1),
                      ("description", str "Timeout in seconds.")
                    ]),
                    ("lock", obj [
                      ("type", str "array"),
                      ("items", obj [("type", str "string")]),
                      ("description", str "Glob patterns for files to hash into qed.lock. Workers cannot modify locked files without detection.")
                    ])
                  ])
                ],
                obj [
                  ("type", str "object"),
                  ("description", str "Spawn an independent LLM agent to review against a prompt."),
                  ("required", arr [str "type", str "prompt"]),
                  ("additionalProperties", bool false),
                  ("properties", obj [
                    ("type", obj [("const", str verifyTypes[1]!)]),
                    ("prompt", obj [
                      ("type", str "string"),
                      ("description", str "Review prompt for the agent.")
                    ]),
                    ("model", obj [
                      ("type", str "string"),
                      ("default", str defaultAgentModel),
                      ("description", str "Model to use for the review.")
                    ]),
                    ("command", obj [
                      ("type", str "string"),
                      ("description", str "Shell command to invoke the agent. Receives prompt via $QED_VERIFIER_PROMPT. Defaults to Claude CLI.")
                    ]),
                    ("timeout", obj [
                      ("type", str "integer"),
                      ("default", num defaultAgentTimeout),
                      ("minimum", num 1),
                      ("description", str "Timeout in seconds.")
                    ])
                  ])
                ],
                obj [
                  ("type", str "object"),
                  ("description", str "Run property-based tests."),
                  ("required", arr [str "type", str "run"]),
                  ("additionalProperties", bool false),
                  ("properties", obj [
                    ("type", obj [("const", str verifyTypes[2]!)]),
                    ("run", obj [
                      ("type", str "string"),
                      ("description", str "Shell command to run property tests.")
                    ]),
                    ("timeout", obj [
                      ("type", str "integer"),
                      ("default", num defaultPropertyTimeout),
                      ("minimum", num 1),
                      ("description", str "Timeout in seconds.")
                    ]),
                    ("lock", obj [
                      ("type", str "array"),
                      ("items", obj [("type", str "string")]),
                      ("description", str "Glob patterns for files to hash into qed.lock. Workers cannot modify locked files without detection.")
                    ])
                  ])
                ],
                obj [
                  ("type", str "object"),
                  ("description", str "Verify a formal proof target."),
                  ("required", arr [str "type", str "prover", str "target"]),
                  ("additionalProperties", bool false),
                  ("properties", obj [
                    ("type", obj [("const", str verifyTypes[3]!)]),
                    ("prover", obj [
                      ("type", str "string"),
                      ("description", str "Proof system. Currently supported: lean4.")
                    ]),
                    ("target", obj [
                      ("type", str "string"),
                      ("description", str "Fully qualified name of the theorem to verify.")
                    ])
                  ])
                ],
                obj [
                  ("type", str "object"),
                  ("description", str "Ask a human to verify. Requires interactive stdin (schedule defaults to 'manual')."),
                  ("required", arr [str "type", str "instruction"]),
                  ("additionalProperties", bool false),
                  ("properties", obj [
                    ("type", obj [("const", str verifyTypes[4]!)]),
                    ("instruction", obj [
                      ("type", str "string"),
                      ("description", str "What the human should verify.")
                    ])
                  ])
                ]
              ])
            ]),
            ("schedule", obj [
              ("type", str "string"),
              ("description", str "When this criterion runs. Defaults: 'always' for command/property/proof, 'heavy' for agent, 'manual' for human."),
              ("enum", arr (schedules.map fun s => DocGen.Schema.str s)),
              ("default", str "always")
            ]),
            ("skip", obj [
              ("type", str "string"),
              ("description", str "Skip this criterion with the given reason. Skipped criteria show [SKIP] in output and do not affect the overall pass/fail result.")
            ])
          ])
        ])
      ]),
      ("maxIterations", obj [
        ("type", str "integer"),
        ("description", str "Maximum worker iterations before giving up. Only valid when worker is present."),
        ("default", num loopConfig.maxIterations),
        ("minimum", num 1)
      ]),
      ("stuckThreshold", obj [
        ("type", str "integer"),
        ("description", str "Consecutive identical failures before declaring stuck. Only valid when worker is present."),
        ("default", num loopConfig.stuckThreshold),
        ("minimum", num 1)
      ])
    ]),
    ("if", obj [
      ("required", arr [str "worker"])
    ]),
    ("then", obj [
      ("description", str "Worker loop mode: worker iterates against criteria.")
    ]),
    ("else", obj [
      ("description", str "Verify mode: single-pass verification, criteria required."),
      ("properties", obj [
        ("criteria", obj [("minItems", num 1)])
      ]),
      ("not", obj [
        ("required", arr [str "maxIterations"])
      ])
    ])
  ]
  schema.render

end DocGen.Schema
