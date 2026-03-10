# Proven properties

> Complete reference for all formally verified theorems in qed.

The `Qed/Proofs/` directory contains formal proofs verified by Lean 4's kernel. All proofs are complete — no `sorry`, no gaps.

## State machine (worker loop)

| File | Theorem | Property |
|------|---------|----------|
| `FinalStates.lean` | `terminal_absorbing` | Terminal states ignore all events — transitioning from a terminal state returns the same state and context |
| `Monotonic.lean` | `iteration_monotonic` | The iteration count never decreases across transitions |
| `NoSkip.lean` | `no_skip_verification` | Cannot reach `passed` without going through `verifying` first |
| `NoSkip.lean` | `worker_before_verification` | `verifying(n)` is only reachable from `workerRunning(n)` or `verifying(n)` |
| `StuckDetection.lean` | `stuck_iff_threshold` | Stuck detection fires iff consecutive failure count reaches the threshold |
| `StuckDetection.lean` | `stuck_when_threshold_reached` | Threshold reached implies stuck state |
| `StuckDetection.lean` | `not_stuck_when_below_threshold` | Below threshold implies retry (workerRunning) |
| `StuckDetection.lean` | `failure_count_update` | Failure count increments on same failures, resets on different failures |
| `Termination.lean` | `verify_someFailed_terminates_or_increments` | Each verify+someFailed step either terminates or increments iteration |
| `Termination.lean` | `fuel_decreases_on_retry` | The fuel measure (maxIterations - iteration) strictly decreases on retry |
| `Termination.lean` | `loop_progress` | Each non-terminal step either terminates or increments iteration (bounded by maxIterations) |
| `Termination.lean` | `loop_terminates` | Full termination: each step terminates or strictly decreases fuel (maxIterations - iteration) |
| `Invariants.lean` | `transition_deterministic` | Equal inputs produce equal outputs — the transition function is deterministic |
| `Invariants.lean` | `ready_unreachable` | No non-terminal transition produces `ready` — the initial state is visited exactly once |
| `Invariants.lean` | `phase_monotonic` | State lifecycle phase (initial → working → terminal) never decreases |
| `Invariants.lean` | `iteration_bounded` | Iteration count never exceeds `maxIterations` (given `maxIterations ≥ 1`) |
| `VerifyMode.lean` | `verify_has_no_worker` | `SpecMode.verify` cannot carry a `WorkerConfig` or `LoopConfig` |
| `VerifyMode.lean` | `verify_independent_of_loop` | Verify mode is independent of the worker loop machinery |

## Worker loop (execution engine)

| File | Theorem | Property |
|------|---------|----------|
| `WorkerLoopProperties.lean` | `step_eq_transition` | The loop's step function is exactly StateMachine.transition |
| `WorkerLoopProperties.lean` | `buildPrompt_empty_failures` | No failures → base prompt returned unchanged |
| `WorkerLoopProperties.lean` | `buildPrompt_nonempty_appends` | Failures → base prompt is extended (not replaced) |
| `WorkerLoopProperties.lean` | `shellQuote_wraps` | shellQuote wraps input in single quotes |
| `WorkerLoopProperties.lean` | `shellQuote_empty` | shellQuote of "" produces "''" |

## Types, output, parser, and TOML parser

| File | Theorem | Property |
|------|---------|----------|
| `TypeProperties.lean` | `isTerminal_decidable` | Every LoopState is either terminal or not |
| `TypeProperties.lean` | `isPassed_iff_pass` | `isPassed` returns true iff the result is `.pass` |
| `TypeProperties.lean` | `isFailed_iff_fail` | `isFailed` returns true iff the result is `.fail` |
| `TypeProperties.lean` | `passed_and_failed_exclusive` | No result is both passed and failed |
| `TypeProperties.lean` | `result_exhaustive` | Every VerificationResult is exactly one of pass, fail, needsHuman, or skipped |
| `TypeProperties.lean` | `result_complete_partition` | Complete partition — every result is exactly one variant; predicates agree |
| `OutputCorrectness.lean` | `allPassed_iff_no_failures` | Pass/fail decision is correct: true iff no result is `.fail` |
| `OutputCorrectness.lean` | `resultsToJson_has_required_fields` | JSON output always contains "spec", "passed", "criteria" fields |
| `OutputCorrectness.lean` | `workerResultsToJson_has_required_fields` | Worker loop JSON always contains "spec", "state", "passed", "criteria" fields |
| `ParserProperties.lean` | `parseCiSchedule_complete` | If parseCiSchedule succeeds, input was "always", "trunk", or "manual" |
| `ParserProperties.lean` | `parseCiSchedule_rejects_invalid` | Any other string produces an error |
| `TomlProperties.lean` | `setNested_no_duplicate_at_leaf` | setNested inserts without duplicates when key is absent |
| `TomlProperties.lean` | `setNested_rejects_duplicate` | setNested returns error when key already exists |
| `TomlProperties.lean` | `setNested_empty_keys` | Empty key path is always rejected |
| `TomlProperties.lean` | `appendArray_empty_keys` | Empty key path is always rejected |
| `TomlProperties.lean` | `appendArray_creates_new` | Absent key creates new single-element array |
| `TomlJsonValidity.lean` | `tomlToJson_total` | tomlToJson always returns Ok or Error (never diverges) |
| `TomlJsonValidity.lean` | `tomlToJson_ok_implies_parseDoc_ok` | Successful conversion implies successful parse |
| `TomlJsonValidity.lean` | `parseDoc_error_implies_tomlToJson_error` | Parse failure propagates to conversion failure |
| `TomlJsonValidity.lean` | `toJson_str` | String values map to JSON strings |
| `TomlJsonValidity.lean` | `toJson_int` | Integer values map to JSON numbers |
| `TomlJsonValidity.lean` | `toJson_bool` | Boolean values map to JSON booleans |
| `TomlJsonValidity.lean` | `toJson_table` | Tables map to JSON objects via toJsonPairs |
| `TomlJsonValidity.lean` | `toJson_array` | Arrays map to JSON arrays via toJsonList |
| `TomlJsonValidity.lean` | `toJson_empty_table` | Empty table produces empty JSON object |
| `TomlJsonValidity.lean` | `toJson_empty_array` | Empty array produces empty JSON array |
| `Roundtrip.lean` | `ciSchedule_roundtrip` | parseCiSchedule inverts ciScheduleToString |
| `Roundtrip.lean` | `verifyType_roundtrip` | parseVerifyType inverts verifyTypeToJson for every constructor |
| `Roundtrip.lean` | `criterion_roundtrip` | parseCriterion inverts criterionToJson |
| `Roundtrip.lean` | `workerConfig_roundtrip` | parseWorkerConfig inverts workerConfigToJson |
| `Roundtrip.lean` | `criteria_list_roundtrip` | Element-wise roundtrip lifts to list-level mapM roundtrip |
| `Roundtrip.lean` | `spec_roundtrip` | **Main theorem:** parseFromJson inverts specToJson for all well-formed specs |
