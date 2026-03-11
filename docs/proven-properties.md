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
| `StuckDetection.lean` | `stuck_when_threshold_reached`               | Threshold reached implies stuck state                                                                                 |
| `StuckDetection.lean` | `not_stuck_when_below_threshold`             | Below threshold implies retry (workerRunning)                                                                         |
| `StuckDetection.lean` | `failure_count_update`                       | Failure count increments on same failures, resets on different failures                                               |
| `Termination.lean`    | `verify_someFailed_outcomes`                 | verify+someFailed produces stuck, maxIterationsReached, or workerRunning                                              |
| `Termination.lean`    | `verify_someFailed_terminates_or_increments` | Each verify+someFailed step either terminates or increments iteration                                                 |
| `Termination.lean`    | `verify_allPassed_terminates`                | verify+allPassed always reaches terminal state (passed)                                                               |
| `Termination.lean`    | `verify_workerDone_stays`                    | verify+workerDone preserves terminal state                                                                            |
| `Termination.lean`    | `workerRunning_transition`                   | workerRunning transitions to verifying, stays, or terminates (integrityViolation)                                     |
| `Termination.lean`    | `fuel_decreases_on_retry`                    | The fuel measure (maxIterations - iteration) strictly decreases on retry                                              |
| `Termination.lean`    | `loop_progress`                              | Each non-terminal step either terminates or increments iteration (bounded by maxIterations)                           |
| `Termination.lean`    | `loop_terminates`                            | **[spec]** Full termination: each step terminates or strictly decreases fuel (maxIterations - iteration)              |
| `Invariants.lean`     | `transition_deterministic`                   | **[spec]** Equal inputs produce equal outputs — the transition function is deterministic                              |
| `Invariants.lean`     | `ready_unreachable`                          | **[spec]** No non-terminal transition produces `ready` — the initial state is visited exactly once                    |
| `Invariants.lean`     | `phase_monotonic`                            | **[spec]** State lifecycle phase (initial → working → terminal) never decreases                                       |
| `Invariants.lean`     | `iteration_bounded`                          | **[spec]** Iteration count never exceeds `maxIterations` (given `maxIterations ≥ 1`)                                  |
| `VerifyMode.lean`     | `verify_has_no_worker`                       | **[spec]** `SpecMode.verify` cannot carry a `WorkerConfig` or `LoopConfig`                                            |
| `VerifyMode.lean`     | `verify_independent_of_loop`                 | **[spec]** Verify mode is independent of the worker loop machinery                                                    |

## Spec integrity

| File                       | Theorem                          | Property                                                                                  |
| -------------------------- | -------------------------------- | ----------------------------------------------------------------------------------------- |
| `IntegrityProperties.lean` | `integrity_violation_terminal`   | integrityViolation event from any non-terminal state produces terminal integrityViolation |
| `IntegrityProperties.lean` | `integrity_violation_absorbing`  | integrityViolation state is absorbing (no event transitions out)                          |
| `IntegrityProperties.lean` | `integrity_violation_not_passed` | integrityViolation from a non-terminal state can never produce passed                     |

## Worker loop (execution engine)

| File                        | Theorem                        | Property                                                               |
| --------------------------- | ------------------------------ | ---------------------------------------------------------------------- |
| `WorkerLoopProperties.lean` | `step_eq_transition`           | **[spec]** The loop's step function is exactly StateMachine.transition |
| `WorkerLoopProperties.lean` | `buildPrompt_empty_failures`   | **[spec]** No failures → base prompt returned unchanged                |
| `WorkerLoopProperties.lean` | `buildPrompt_nonempty_appends` | **[spec]** Failures → base prompt is extended (not replaced)           |
| `WorkerLoopProperties.lean` | `shellQuote_wraps`             | **[spec]** shellQuote wraps input in single quotes                     |
| `WorkerLoopProperties.lean` | `shellQuote_empty`             | **[spec]** shellQuote of "" produces "''"                              |

## Types, output, parser, and TOML parser

| File                     | Theorem                                   | Property                                                                                 |
| ------------------------ | ----------------------------------------- | ---------------------------------------------------------------------------------------- |
| `TypeProperties.lean`    | `isTerminal_decidable`                    | Every LoopState is either terminal or not                                                |
| `TypeProperties.lean`    | `isPassed_iff_pass`                       | `isPassed` returns true iff the result is `.pass`                                        |
| `TypeProperties.lean`    | `isFailed_iff_fail`                       | `isFailed` returns true iff the result is `.fail`                                        |
| `TypeProperties.lean`    | `passed_and_failed_exclusive`             | No result is both passed and failed                                                      |
| `TypeProperties.lean`    | `result_exhaustive`                       | Every VerificationResult is exactly one of pass, fail, needsHuman, or skipped            |
| `TypeProperties.lean`    | `result_complete_partition`               | **[spec]** Complete partition — every result is exactly one variant; predicates agree    |
| `OutputCorrectness.lean` | `allPassed_iff_no_failures`               | **[spec]** Pass/fail decision is correct: true iff no result is `.fail`                  |
| `OutputCorrectness.lean` | `resultsToJson_has_required_fields`       | **[spec]** JSON output always contains "spec", "passed", "criteria" fields               |
| `OutputCorrectness.lean` | `workerResultsToJson_has_required_fields` | **[spec]** Worker loop JSON always contains "spec", "state", "passed", "criteria" fields |
| `ParserProperties.lean`  | `parseSchedule_complete`                  | **[spec]** If parseSchedule succeeds, input was "always" or "manual"                     |
| `ParserProperties.lean`  | `parseSchedule_always`                    | parseSchedule "always" = .ok .always                                                     |
| `ParserProperties.lean`  | `parseSchedule_manual`                    | parseSchedule "manual" = .ok .manual                                                     |
| `ParserProperties.lean`  | `parseSchedule_rejects_invalid`           | **[spec]** Any other string produces an error                                            |
| `TomlProperties.lean`    | `setNested_no_duplicate_at_leaf`          | setNested inserts without duplicates when key is absent                                  |
| `TomlProperties.lean`    | `setNested_rejects_duplicate`             | **[spec]** setNested returns error when key already exists                               |
| `TomlProperties.lean`    | `setNested_empty_keys`                    | Empty key path is always rejected                                                        |
| `TomlProperties.lean`    | `appendArray_empty_keys`                  | Empty key path is always rejected                                                        |
| `TomlProperties.lean`    | `appendArray_creates_new`                 | Absent key creates new single-element array                                              |
| `TomlJsonValidity.lean`  | `tomlToJson_total`                        | **[spec]** tomlToJson always returns Ok or Error (never diverges)                        |
| `TomlJsonValidity.lean`  | `tomlToJson_ok_implies_parseDoc_ok`       | **[spec]** Successful conversion implies successful parse                                |
| `TomlJsonValidity.lean`  | `parseDoc_error_implies_tomlToJson_error` | **[spec]** Parse failure propagates to conversion failure                                |
| `TomlJsonValidity.lean`  | `toJson_str`                              | String values map to JSON strings                                                        |
| `TomlJsonValidity.lean`  | `toJson_int`                              | Integer values map to JSON numbers                                                       |
| `TomlJsonValidity.lean`  | `toJson_bool`                             | Boolean values map to JSON booleans                                                      |
| `TomlJsonValidity.lean`  | `toJson_table`                            | Tables map to JSON objects via toJsonPairs                                               |
| `TomlJsonValidity.lean`  | `toJson_array`                            | Arrays map to JSON arrays via toJsonList                                                 |
| `TomlJsonValidity.lean`  | `toJson_empty_table`                      | Empty table produces empty JSON object                                                   |
| `TomlJsonValidity.lean`  | `toJson_empty_array`                      | Empty array produces empty JSON array                                                    |
| `Roundtrip.lean`         | `schedule_roundtrip`                      | parseSchedule inverts scheduleToString                                                   |
| `Roundtrip.lean`         | `verifyType_roundtrip`                    | parseVerifyType inverts verifyTypeToJson for every constructor                           |
| `Roundtrip.lean`         | `criterion_roundtrip`                     | parseCriterion inverts criterionToJson                                                   |
| `Roundtrip.lean`         | `workerConfig_roundtrip`                  | parseWorkerConfig inverts workerConfigToJson                                             |
| `Roundtrip.lean`         | `criteria_list_roundtrip`                 | Element-wise roundtrip lifts to list-level mapM roundtrip                                |
| `Roundtrip.lean`         | `spec_verify_roundtrip`                   | parseFromJson inverts specToJson for verify-mode specs                                   |
| `Roundtrip.lean`         | `spec_workerLoop_roundtrip`               | parseFromJson inverts specToJson for workerLoop-mode specs                               |
| `Roundtrip.lean`         | `spec_roundtrip`                          | **[spec]** **Main theorem:** parseFromJson inverts specToJson for all well-formed specs  |
