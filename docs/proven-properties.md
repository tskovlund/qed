# Proven properties

> Complete reference for all formally verified theorems in qed.

The `Qed/Proofs/` directory contains formal proofs verified by Lean 4's kernel. All proofs are complete — no `sorry`, no gaps. Theorems marked with **[spec]** are verified as acceptance criteria in `specs/`.

## State machine (worker loop)

| File                  | Theorem                                      | Property                                                                                                              |
| --------------------- | -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `FinalStates.lean`    | `terminal_absorbing`                         | **[spec]** Terminal states ignore all events — transitioning from a terminal state returns the same state and context |
| `Monotonic.lean`      | `iteration_monotonic`                        | **[spec]** The iteration count never decreases across transitions, or the result is terminal                          |
| `NoSkip.lean`         | `no_skip_verification`                       | **[spec]** Cannot reach `passed` without going through `verifying` first                                              |
| `NoSkip.lean`         | `worker_before_verification`                 | `verifying(n)` is only reachable from `workerRunning(n)` or `verifying(n)`                                            |
| `StuckDetection.lean` | `stuck_iff_threshold`                        | **[spec]** Stuck detection fires iff consecutive failure count reaches the threshold                                  |
| `StuckDetection.lean` | `failure_count_update`                       | Failure count increments on same failures, resets on different failures                                               |
| `Termination.lean`    | `verify_someFailed_outcomes`                 | verify+someFailed produces stuck, maxIterationsReached, or workerRunning                                              |
| `Termination.lean`    | `verify_someFailed_terminates_or_increments` | Each verify+someFailed step either terminates or increments iteration                                                 |
| `Termination.lean`    | `verify_allPassed_terminates`                | verify+allPassed always reaches terminal state (passed)                                                               |
| `Termination.lean`    | `verify_workerDone_stays`                    | verify+workerDone preserves terminal state                                                                            |
| `Termination.lean`    | `workerRunning_transition`                   | workerRunning transitions to verifying, stays, or terminates (integrityViolation)                                     |
| `Termination.lean`    | `fuel_decreases_on_retry`                    | The fuel measure (maxIterations - iteration) strictly decreases on retry                                              |
| `Termination.lean`    | `loop_progress`                              | Each non-terminal step either terminates or increments iteration (bounded by maxIterations)                           |
| `Termination.lean`    | `loop_terminates`                            | **[spec]** Full termination: each step terminates or strictly decreases fuel (maxIterations - iteration)              |
| `Termination.lean`    | `progress_or_terminal`                       | **[spec]** Every state-changing non-terminal transition either terminates or strictly increases the progress measure  |
| `Invariants.lean`     | `transition_deterministic`                   | **[spec]** Equal inputs produce equal outputs — the transition function is deterministic                              |
| `Invariants.lean`     | `ready_unreachable`                          | **[spec]** No non-terminal transition produces `ready` — the initial state is visited exactly once                    |
| `Invariants.lean`     | `phase_monotonic`                            | **[spec]** State lifecycle phase (initial → working → terminal) never decreases                                       |
| `Invariants.lean`     | `iteration_bounded`                          | **[spec]** Iteration count never exceeds `maxIterations` (given `maxIterations ≥ 1`)                                  |
| `Invariants.lean`     | `ready_always_advances`                      | **[spec]** Ready state always advances — transitions to workerRunning(1) or integrityViolation                        |
| `Invariants.lean`     | `lifecycle_ordering`                         | **[spec]** Complete 5-way characterization of all non-terminal transitions (terminates, self-loops, or advances)      |

## Spec integrity

| File                       | Theorem                          | Property                                                                                             |
| -------------------------- | -------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `IntegrityProperties.lean` | `integrity_violation_terminal`   | **[spec]** integrityViolation event from any non-terminal state produces terminal integrityViolation |
| `IntegrityProperties.lean` | `integrity_violation_absorbing`  | integrityViolation state is absorbing (no event transitions out)                                     |
| `IntegrityProperties.lean` | `integrity_violation_not_passed` | **[spec]** integrityViolation from a non-terminal state can never produce passed                     |

## Verify mode

| File              | Theorem                      | Property                                                                   |
| ----------------- | ---------------------------- | -------------------------------------------------------------------------- |
| `VerifyMode.lean` | `verify_has_no_worker`       | **[spec]** `SpecMode.verify` cannot carry a `WorkerConfig` or `LoopConfig` |
| `VerifyMode.lean` | `verify_independent_of_loop` | **[spec]** Verify mode is independent of the worker loop machinery         |

## Worker loop (execution engine)

| File                        | Theorem                        | Property                                                               |
| --------------------------- | ------------------------------ | ---------------------------------------------------------------------- |
| `WorkerLoopProperties.lean` | `step_eq_transition`           | **[spec]** The loop's step function is exactly StateMachine.transition |
| `WorkerLoopProperties.lean` | `buildPrompt_empty_failures`   | **[spec]** No failures → base prompt returned unchanged                |
| `WorkerLoopProperties.lean` | `buildPrompt_nonempty_appends` | **[spec]** Failures → base prompt is extended (not replaced)           |
| `WorkerLoopProperties.lean` | `shellQuote_wraps`             | **[spec]** shellQuote wraps input in single quotes                     |
| `WorkerLoopProperties.lean` | `shellQuote_empty`             | **[spec]** shellQuote of "" produces "''"                              |

## Types and output

| File                     | Theorem                                      | Property                                                                                 |
| ------------------------ | -------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `TypeProperties.lean`    | `isTerminal_iff`                             | isTerminal returns true iff state is one of the five terminal states                     |
| `TypeProperties.lean`    | `isPassed_iff_pass`                          | `isPassed` returns true iff the result is `.pass`                                        |
| `TypeProperties.lean`    | `isFailed_iff_fail`                          | `isFailed` returns true iff the result is `.fail`                                        |
| `TypeProperties.lean`    | `isSkipped_iff_skipped`                      | `isSkipped` returns true iff the result is `.skipped`                                    |
| `TypeProperties.lean`    | `predicates_mutually_exclusive`              | isPassed, isFailed, isSkipped are pairwise mutually exclusive                            |
| `TypeProperties.lean`    | `result_exhaustive`                          | Every VerificationResult is exactly one of pass, fail, needsHuman, or skipped            |
| `TypeProperties.lean`    | `result_complete_partition`                  | **[spec]** Complete partition — every result is exactly one variant; predicates agree    |
| `OutputCorrectness.lean` | `allExecutionsPassed_iff_no_failures`        | **[spec]** Pass/fail decision is correct: true iff no execution is `.fail`               |
| `OutputCorrectness.lean` | `executionsToJson_has_required_fields`       | **[spec]** JSON output always contains "spec", "passed", "criteria" fields               |
| `OutputCorrectness.lean` | `workerExecutionsToJson_has_required_fields` | **[spec]** Worker loop JSON always contains "spec", "state", "passed", "criteria" fields |

## Verifier

| File                      | Theorem                          | Property                                                                                 |
| ------------------------- | -------------------------------- | ---------------------------------------------------------------------------------------- |
| `VerifierProperties.lean` | `isIdentChar_eq_validModuleChar` | isIdentChar checks the same character set as isValidModuleName                           |
| `VerifierProperties.lean` | `targetToModule_iff`             | **[spec]** targetToModule returns module prefix iff target has ≥2 dot-separated parts    |
| `VerifierProperties.lean` | `moduleToPath_ends_with_lean`    | moduleToPath output always ends with ".lean"                                             |
| `VerifierProperties.lean` | `moduleToPath_of_targetToModule` | Composing targetToModule and moduleToPath gives the expected file path                   |
| `VerifierProperties.lean` | `isValidModuleName_iff`          | **[spec]** Valid iff all dot-separated parts are non-empty identifier-char-only segments |
| `VerifierProperties.lean` | `containsSorry_iff`              | **[spec]** containsSorry detects exactly standalone sorry occurrences                    |

## Shell command construction

`buildShellCommand` splices environment variable values into a string handed to `/bin/sh -c`, so it is the shell-injection surface.

| File                   | Theorem                          | Property                                                                       |
| ---------------------- | -------------------------------- | ------------------------------------------------------------------------------ |
| `ShellProperties.lean` | `shellQuote_shim_eq`             | The `WorkerLoop.shellQuote` re-export is exactly `Shell.shellQuote`            |
| `ShellProperties.lean` | `buildShellCommand_empty_env`    | With no environment variables the command is passed through untouched          |
| `ShellProperties.lean` | `buildShellCommand_single`       | One variable expands to one `export` with a shell-quoted value, command last   |
| `ShellProperties.lean` | `buildShellCommand_pair`         | Two variables quote both values and still leave the command last               |
| `ShellProperties.lean` | `buildShellCommand_command_last` | For any non-empty environment the command is the trailing segment after `"; "` |

**Known gap:** quoting is proven for the zero-, one-, and two-variable cases plus the structural "command is last" property for arbitrary lists, but _not_ "every value in an arbitrary-length list is quoted". That statement requires induction over `String.intercalate`'s accumulator helper, which Lean 4.28.0 does not expose as an accessible constant.

## Parser and serialization

| File                    | Theorem                     | Property                                                                                       |
| ----------------------- | --------------------------- | ---------------------------------------------------------------------------------------------- |
| `ParserProperties.lean` | `parseSchedule_iff`         | **[spec]** parseSchedule accepts exactly "always", "heavy", "manual" — rejects everything else |
| `Roundtrip.lean`        | `schedule_roundtrip`        | parseSchedule inverts scheduleToString                                                         |
| `Roundtrip.lean`        | `verifyType_roundtrip`      | parseVerifyType inverts verifyTypeToJson for every constructor                                 |
| `Roundtrip.lean`        | `criterion_roundtrip`       | parseCriterion inverts criterionToJson                                                         |
| `Roundtrip.lean`        | `workerConfig_roundtrip`    | parseWorkerConfig inverts workerConfigToJson                                                   |
| `Roundtrip.lean`        | `criteria_list_roundtrip`   | Element-wise roundtrip lifts to list-level mapM roundtrip                                      |
| `Roundtrip.lean`        | `spec_verify_roundtrip`     | parseFromJson inverts specToJson for verify-mode specs                                         |
| `Roundtrip.lean`        | `spec_workerLoop_roundtrip` | parseFromJson inverts specToJson for workerLoop-mode specs                                     |
| `Roundtrip.lean`        | `spec_roundtrip`            | **[spec]** **Main theorem:** parseFromJson inverts specToJson for all well-formed specs        |

## Contract lock file

The lock file (`qed.lock`) records content hashes for locked artifacts. Writer and reader are proven to agree on every field.

| File                 | Theorem                         | Property                                                                                 |
| -------------------- | ------------------------------- | ---------------------------------------------------------------------------------------- |
| `LockRoundtrip.lean` | `artifact_roundtrip`            | parseArtifact inverts artifactToJson                                                     |
| `LockRoundtrip.lean` | `artifacts_list_roundtrip`      | Element-wise artifact roundtrip lifts to list-level mapM roundtrip                       |
| `LockRoundtrip.lean` | `criterionLock_roundtrip`       | parseCriterionLock inverts criterionLockToJson                                           |
| `LockRoundtrip.lean` | `criterionLocks_list_roundtrip` | Element-wise criterion-lock roundtrip lifts to lists                                     |
| `LockRoundtrip.lean` | `specLock_roundtrip`            | parseSpecLock inverts specLockToJson                                                     |
| `LockRoundtrip.lean` | `specLocks_list_roundtrip`      | Element-wise spec-lock roundtrip lifts to lists                                          |
| `LockRoundtrip.lean` | `lockFile_roundtrip`            | **Main theorem:** parseLockFileFromJson inverts lockFileToJson for the supported version |
| `LockRoundtrip.lean` | `generated_lockFile_roundtrip`  | The roundtrip holds unconditionally for lock files qed generates                         |

**Scope:** these cover the `LockFile ↔ Json` layer. The outer string layer (`serializeLockFile` = `Json.pretty`, `parseLockFile` = `Json.parse` then the above) rests on `Json.parse ∘ Json.pretty = id` — a property of Lean's JSON library, not of qed — and is covered by `testLockFileRoundtrip` instead. This is the same boundary the spec roundtrip draws at `specToJson`/`parseFromJson`.

## TOML parser

| File                    | Theorem                                   | Property                                                                 |
| ----------------------- | ----------------------------------------- | ------------------------------------------------------------------------ |
| `TomlProperties.lean`   | `setNested_no_duplicate_at_leaf`          | setNested inserts without duplicates when key is absent                  |
| `TomlProperties.lean`   | `setNested_rejects_duplicate`             | **[spec]** setNested returns error when key already exists               |
| `TomlProperties.lean`   | `setNested_empty_keys`                    | Empty key path is always rejected                                        |
| `TomlProperties.lean`   | `appendArray_empty_keys`                  | Empty key path is always rejected                                        |
| `TomlProperties.lean`   | `appendArray_creates_new`                 | Absent key creates new single-element array                              |
| `TomlJsonValidity.lean` | `tomlToJson_total`                        | **[spec]** tomlToJson always returns Ok or Error (never diverges)        |
| `TomlJsonValidity.lean` | `tomlToJson_ok_implies_parseDoc_ok`       | **[spec]** Successful conversion implies successful parse                |
| `TomlJsonValidity.lean` | `parseDoc_error_implies_tomlToJson_error` | **[spec]** Parse failure propagates to conversion failure                |
| `TomlJsonValidity.lean` | `toJson_str`                              | String values map to JSON strings                                        |
| `TomlJsonValidity.lean` | `toJson_int`                              | Integer values map to JSON numbers                                       |
| `TomlJsonValidity.lean` | `toJson_bool`                             | Boolean values map to JSON booleans                                      |
| `TomlJsonValidity.lean` | `toJson_table`                            | Tables map to JSON objects via toJsonPairs                               |
| `TomlJsonValidity.lean` | `toJson_array`                            | Arrays map to JSON arrays via toJsonList                                 |
| `TomlJsonValidity.lean` | `toJson_empty_table`                      | Empty table produces empty JSON object                                   |
| `TomlJsonValidity.lean` | `toJson_empty_array`                      | Empty array produces empty JSON array                                    |
| `TomlRoundtrip.lean`    | `schedule_toml_eq_json`                   | TOML and JSON schedule serializers produce the same string               |
| `TomlRoundtrip.lean`    | `verifyType_toml_json_eq`                 | TOML verify-type pairs convert to the same JSON as the serializer        |
| `TomlRoundtrip.lean`    | `criterion_toml_json_eq`                  | TOML criterion pairs convert to the same JSON as the serializer          |
| `TomlRoundtrip.lean`    | `criteria_list_toml_json_eq`              | Element-wise criterion equivalence lifts to lists                        |
| `TomlRoundtrip.lean`    | `workerConfig_toml_json_eq`               | TOML worker config pairs convert to the same JSON as the serializer      |
| `TomlRoundtrip.lean`    | `spec_toml_json_eq`                       | **[spec]** TOML serializer produces the same JSON as the JSON serializer |
| `TomlRoundtrip.lean`    | `toml_spec_roundtrip`                     | **[spec]** Parsing TOML-serialized spec recovers the original spec       |
