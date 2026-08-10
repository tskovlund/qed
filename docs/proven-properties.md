# Proven properties

> What qed's formal proofs guarantee, by subsystem.

Every theorem in `Qed/Proofs/` is checked by Lean 4's kernel. There is no `sorry` and no `native_decide` — nothing in this document rests on the compiler's evaluator or on an unfinished argument. Theorems marked **[spec]** are also acceptance criteria in `specs/`, so qed re-checks them on itself every time it verifies its own repo.

## The worker loop always terminates

A qed run cannot hang or spin forever. Each pass through the loop either reaches a terminal state or strictly decreases the fuel measure `maxIterations - iteration`, and fuel is a natural number, so the loop stops after at most `maxIterations` retries. The iteration count is bounded by the configured maximum, never rolls backwards, and the lifecycle only moves forward: `ready → workerRunning → verifying → terminal`.

| File               | Theorem                                      | Guarantee                                                                        |
| ------------------ | -------------------------------------------- | -------------------------------------------------------------------------------- |
| `Termination.lean` | `loop_terminates`                            | **[spec]** Every step terminates or strictly decreases fuel                      |
| `Termination.lean` | `progress_or_terminal`                       | **[spec]** Every state-changing step terminates or advances the progress measure |
| `Termination.lean` | `loop_progress`                              | A retry increments the iteration and stays within `maxIterations`                |
| `Termination.lean` | `fuel_decreases_on_retry`                    | The fuel measure strictly decreases on retry                                     |
| `Termination.lean` | `verify_someFailed_outcomes`                 | A failed verification yields stuck, maxIterationsReached, or the next iteration  |
| `Termination.lean` | `verify_someFailed_terminates_or_increments` | Each failed verification terminates or increments the iteration                  |
| `Termination.lean` | `verify_allPassed_terminates`                | A fully passing verification ends the run                                        |
| `Termination.lean` | `verify_workerDone_stays`                    | A repeated `workerDone` holds the iteration steady                               |
| `Termination.lean` | `workerRunning_transition`                   | A running worker advances to verification, stays, or terminates                  |
| `Invariants.lean`  | `iteration_bounded`                          | **[spec]** The iteration count never exceeds `maxIterations`                     |
| `Monotonic.lean`   | `iteration_monotonic`                        | **[spec]** The iteration count never decreases                                   |
| `Invariants.lean`  | `phase_monotonic`                            | **[spec]** The lifecycle phase never moves backwards                             |

## The orchestrator cannot skip verification or resurrect a finished run

`passed` is reachable only from `verifying`, so no code path can report success without having verified it. Terminal states absorb every event, so a finished run stays finished. The initial `ready` state is entered exactly once.

| File               | Theorem                      | Guarantee                                                              |
| ------------------ | ---------------------------- | ---------------------------------------------------------------------- |
| `NoSkip.lean`      | `no_skip_verification`       | **[spec]** `passed` is reachable only from `verifying`                 |
| `NoSkip.lean`      | `worker_before_verification` | `verifying(n)` is reachable only from `workerRunning(n)` or itself     |
| `FinalStates.lean` | `terminal_absorbing`         | **[spec]** A terminal state ignores every event                        |
| `Invariants.lean`  | `ready_unreachable`          | **[spec]** No transition returns to `ready`                            |
| `Invariants.lean`  | `ready_always_advances`      | **[spec]** `ready` always advances on the first event                  |
| `Invariants.lean`  | `lifecycle_ordering`         | **[spec]** Complete five-way characterization of every live transition |

## Stuck runs are detected exactly at the threshold

A worker repeating the same failures is caught when — and only when — the consecutive failure count reaches `stuckThreshold`. The count rises on identical failures and resets when the failures change, so a worker making different mistakes is given the retries it was configured for.

| File                  | Theorem                | Guarantee                                                          |
| --------------------- | ---------------------- | ------------------------------------------------------------------ |
| `StuckDetection.lean` | `stuck_iff_threshold`  | **[spec]** Stuck fires iff the failure count reaches the threshold |
| `StuckDetection.lean` | `failure_count_update` | The count carries forward correctly into the next state            |

## A tampered spec stops the run

Once an integrity violation is raised, the loop lands in `integrityViolation` from any live state, cannot leave it, and can never reach `passed`. Work done under a modified spec is never reported as success.

| File                   | Theorem                          | Guarantee                                                 |
| ---------------------- | -------------------------------- | --------------------------------------------------------- |
| `IntegrityEvents.lean` | `integrity_violation_terminal`   | **[spec]** A violation from any live state stops the loop |
| `IntegrityEvents.lean` | `integrity_violation_absorbing`  | No event transitions out of a violation                   |
| `IntegrityEvents.lean` | `integrity_violation_not_passed` | **[spec]** A violation can never yield `passed`           |

## The execution engine drives the proven state machine and nothing else

`WorkerLoop.step` is definitionally `StateMachine.transition`, so every guarantee above applies to the code that actually runs. The prompt an operator writes is passed through unchanged when nothing has failed, and is extended rather than replaced when failure feedback is added.

| File                        | Theorem                        | Guarantee                                                    |
| --------------------------- | ------------------------------ | ------------------------------------------------------------ |
| `WorkerLoopProperties.lean` | `step_eq_transition`           | **[spec]** The loop's step function is the proven transition |
| `WorkerLoopProperties.lean` | `buildPrompt_empty_failures`   | **[spec]** No failures leaves the prompt untouched           |
| `WorkerLoopProperties.lean` | `buildPrompt_nonempty_appends` | **[spec]** Failure feedback extends the operator's prompt    |

## Nothing a caller supplies is read as shell syntax

`Shell.shellQuote` turns any string into exactly one POSIX shell word that decodes back to the original — quotes, `$(…)`, backticks, separators, whitespace and newlines included. The proof is a round-trip against a model of POSIX single-quote parsing, so it rules out the failure mode that matters: a value closing the quote early and exposing its remainder to the shell. Environment values reach `/bin/sh -c` only through that function, and the command being run is always the trailing segment, never spliced into the middle of an export.

| File                   | Theorem                          | Guarantee                                                                |
| ---------------------- | -------------------------------- | ------------------------------------------------------------------------ |
| `ShellProperties.lean` | `shellQuote_is_one_word`         | **[spec]** Every string quotes to one shell word that decodes back to it |
| `ShellProperties.lean` | `shellQuote_empty`               | **[spec]** The empty string quotes to `''`                               |
| `ShellProperties.lean` | `readBody_escapeQuotes`          | The escaper is inverted by POSIX single-quote decoding                   |
| `ShellProperties.lean` | `shellQuote_toList`              | The quoted form is the escaped body between two quotes                   |
| `ShellProperties.lean` | `buildShellCommand_single`       | Values reach the shell only through `shellQuote`                         |
| `ShellProperties.lean` | `buildShellCommand_command_last` | **[spec]** The command is always the trailing segment                    |

## Glob patterns cannot escape into the shell

`ContractLock.expandGlob` sends a caller-supplied pattern through two shell layers — single quotes inside `bash -c`, itself under `/bin/sh -c` — with `isValidGlobPattern` as the only barrier. No character of an accepted pattern is a shell metacharacter, and an accepted pattern is never empty. The policy is not vacuously safe: the patterns qed's own specs use are accepted.

| File                  | Theorem                                      | Guarantee                                                         |
| --------------------- | -------------------------------------------- | ----------------------------------------------------------------- |
| `GlobProperties.lean` | `isValidGlobPattern_excludes_metacharacters` | No character of an accepted pattern can break out of either shell |
| `GlobProperties.lean` | `isValidGlobPattern_nonempty`                | An accepted pattern is never empty                                |
| `GlobProperties.lean` | `accepts_real_patterns`                      | Real glob patterns are accepted                                   |

`isValidGlobPattern` iterates `pattern.toList` rather than `String.all` because the string iterator ships no reduction lemmas, which would leave the property above unstatable.

## Proof targets resolve safely, and `sorry` cannot slip through

A proof criterion's target is split into a module and a theorem name, and the module name is validated before it is interpolated into `lake build`. An accepted name is drawn entirely from letters, digits, `_`, `'` and `.`, so it cannot carry shell syntax. Sorry detection fires on standalone occurrences only — no missed `sorry`, and no false positive on an identifier like `sorryHandler`.

| File                      | Theorem                 | Guarantee                                                           |
| ------------------------- | ----------------------- | ------------------------------------------------------------------- |
| `VerifierProperties.lean` | `targetToModule_iff`    | **[spec]** A target resolves iff it has a module and a theorem part |
| `VerifierProperties.lean` | `isValidModuleName_iff` | **[spec]** Accepted module names carry no shell metacharacters      |
| `VerifierProperties.lean` | `containsSorry_iff`     | **[spec]** `sorry` is detected exactly on identifier boundaries     |

## `.qedignore` matching is total and its glob semantics are proven

Glob matching terminates on every input — the matcher recurses only on arguments that decrease `pattern.length + name.length`, with the bracket case justified by the fact that a bracket expression always consumes at least its closing `]`. Nothing about `.qedignore` handling is opaque to the kernel.

The wildcards mean what the documentation says. A leading `*` matches exactly when some suffix of the name matches the rest of the pattern, which makes a bare `*` match everything including nested paths — `*` deliberately crosses `/`, while `?` deliberately does not. A pattern with no wildcards is an exact-match test: it matches its own text and nothing else, so `archive` never accidentally ignores `archived-specs`.

Blank lines and comments never become patterns. Precedence is last-matching-pattern-wins in both directions: a trailing plain pattern ignores a spec, a trailing `!` pattern brings it back.

| File                    | Theorem                        | Guarantee                                                                 |
| ----------------------- | ------------------------------ | ------------------------------------------------------------------------- |
| `IgnoreProperties.lean` | `matchGlob_star_iff_suffix`    | **[spec]** `*` matches iff some suffix of the name matches the rest       |
| `IgnoreProperties.lean` | `star_matches_everything`      | **[spec]** A bare `*` matches every name, separators included             |
| `IgnoreProperties.lean` | `question_matches_one`         | **[spec]** `?` matches exactly one character and never `/`                |
| `IgnoreProperties.lean` | `literal_matches_iff`          | **[spec]** A wildcard-free pattern matches its own text and nothing else  |
| `IgnoreProperties.lean` | `literal_star_matches_prefix`  | **[spec]** A literal prefix plus `*` matches every name with that prefix  |
| `IgnoreProperties.lean` | `parseIgnoreFile_no_comments`  | **[spec]** Comment lines never become patterns                            |
| `IgnoreProperties.lean` | `parseIgnoreFile_no_empty`     | Blank lines never become patterns                                         |
| `IgnoreProperties.lean` | `shouldIgnore_append_negated`  | **[spec]** A trailing matching `!` pattern un-ignores the spec            |
| `IgnoreProperties.lean` | `shouldIgnore_append_positive` | A trailing matching pattern ignores the spec                              |
| `Ignore.lean`           | `scanBracket_shrinks`          | A bracket expression consumes at least its `]` — the termination argument |
| `Ignore.lean`           | `matchBracket_shrinks`         | The same, through the optional leading `!`                                |

## A spec survives serialization unchanged

Reading back a spec qed wrote recovers it exactly, in both formats: the JSON parser is a proven inverse of the JSON serializer, and the TOML serializer is proven to produce the same JSON as the JSON serializer, so the TOML path inherits the same guarantee. A renamed or dropped field breaks the build instead of quietly changing what a spec means.

| File                    | Theorem                      | Guarantee                                                          |
| ----------------------- | ---------------------------- | ------------------------------------------------------------------ |
| `Roundtrip.lean`        | `spec_roundtrip`             | **[spec]** Parsing a serialized spec recovers it exactly           |
| `Roundtrip.lean`        | `spec_verify_roundtrip`      | The roundtrip holds for verify-mode specs                          |
| `Roundtrip.lean`        | `spec_workerLoop_roundtrip`  | The roundtrip holds for worker-loop specs                          |
| `Roundtrip.lean`        | `criterion_roundtrip`        | Every criterion field survives the roundtrip                       |
| `Roundtrip.lean`        | `criteria_list_roundtrip`    | The criterion roundtrip lifts to lists                             |
| `Roundtrip.lean`        | `workerConfig_roundtrip`     | Every worker config field survives the roundtrip                   |
| `Roundtrip.lean`        | `verifyType_roundtrip`       | Every verification type survives the roundtrip                     |
| `Roundtrip.lean`        | `schedule_roundtrip`         | Every schedule survives the roundtrip                              |
| `TomlRoundtrip.lean`    | `toml_spec_roundtrip`        | **[spec]** Parsing a TOML-serialized spec recovers it exactly      |
| `TomlRoundtrip.lean`    | `spec_toml_json_eq`          | The TOML serializer agrees with the JSON serializer                |
| `TomlRoundtrip.lean`    | `criterion_toml_json_eq`     | Criterion pairs agree between the two serializers                  |
| `TomlRoundtrip.lean`    | `criteria_list_toml_json_eq` | The criterion agreement lifts to lists                             |
| `TomlRoundtrip.lean`    | `workerConfig_toml_json_eq`  | Worker config pairs agree between the two serializers              |
| `TomlRoundtrip.lean`    | `verifyType_toml_json_eq`    | Verification type pairs agree between the two serializers          |
| `TomlRoundtrip.lean`    | `schedule_toml_eq_json`      | Schedules agree between the two serializers                        |
| `ParserProperties.lean` | `parseSchedule_iff`          | **[spec]** `parseSchedule` accepts exactly the three valid strings |

## A malformed lock file cannot silently corrupt state

`qed.lock` records the content hashes that make verification results meaningful. The reader is a proven inverse of the writer at every level — artifact, criterion, spec, file — so a lock file qed wrote always reads back identically, and a field renamed on one side breaks the build rather than degrading integrity checking in silence. Only the supported format version is accepted; every other version is rejected outright.

| File                 | Theorem                         | Guarantee                                               |
| -------------------- | ------------------------------- | ------------------------------------------------------- |
| `LockRoundtrip.lean` | `lockFile_roundtrip`            | The reader inverts the writer for the supported version |
| `LockRoundtrip.lean` | `generated_lockFile_roundtrip`  | Every lock file qed writes reads back exactly           |
| `LockRoundtrip.lean` | `specLock_roundtrip`            | Spec entries survive the roundtrip                      |
| `LockRoundtrip.lean` | `criterionLock_roundtrip`       | Criterion entries survive the roundtrip                 |
| `LockRoundtrip.lean` | `artifact_roundtrip`            | Artifact path and hash survive the roundtrip            |
| `LockRoundtrip.lean` | `specLocks_list_roundtrip`      | The spec roundtrip lifts to lists                       |
| `LockRoundtrip.lean` | `criterionLocks_list_roundtrip` | The criterion roundtrip lifts to lists                  |
| `LockRoundtrip.lean` | `artifacts_list_roundtrip`      | The artifact roundtrip lifts to lists                   |

## A duplicate TOML key is an error, and parse errors always surface

Defining the same key twice in a spec fails loudly instead of silently overwriting. A TOML parse failure always propagates to the conversion result, so a broken spec file can never be read as an empty one.

| File                    | Theorem                                   | Guarantee                                                   |
| ----------------------- | ----------------------------------------- | ----------------------------------------------------------- |
| `TomlProperties.lean`   | `setNested_rejects_duplicate`             | **[spec]** A duplicate key is an error, not an overwrite    |
| `TomlProperties.lean`   | `setNested_no_duplicate_at_leaf`          | A fresh key is appended, leaving existing entries untouched |
| `TomlJsonValidity.lean` | `parseDoc_error_implies_tomlToJson_error` | **[spec]** Parse errors are never swallowed                 |
| `TomlJsonValidity.lean` | `tomlToJson_ok_implies_parseDoc_ok`       | **[spec]** A converted document was really parsed as TOML   |

## The pass/fail decision and the JSON contract are correct

A run passes exactly when no criterion failed. Every result is exactly one of pass, fail, needsHuman, or skipped, and the predicates the decision is built from agree with the constructor. The `--json` output always carries the fields consumers depend on.

| File                     | Theorem                                      | Guarantee                                                         |
| ------------------------ | -------------------------------------------- | ----------------------------------------------------------------- |
| `OutputCorrectness.lean` | `allExecutionsPassed_iff_no_failures`        | **[spec]** A run passes iff no criterion failed                   |
| `OutputCorrectness.lean` | `executionsToJson_has_required_fields`       | **[spec]** Verify output always has `spec`, `passed`, `criteria`  |
| `OutputCorrectness.lean` | `workerExecutionsToJson_has_required_fields` | **[spec]** Worker output adds `state` to the same contract        |
| `TypeProperties.lean`    | `result_complete_partition`                  | **[spec]** Every result is exactly one variant, predicates agree  |
| `TypeProperties.lean`    | `isTerminal_iff`                             | `isTerminal` is true exactly on the five terminal states          |
| `VerifyMode.lean`        | `verify_has_no_worker`                       | **[spec]** A verify-mode spec cannot carry a worker configuration |

## Verification boundary

The proofs cover qed's pure core. Two architectural facts define where that core ends.

**IO is tested, not proven.** Process spawning, file reading, git inspection, and terminal output live in `Main.lean`, `Verifier.lean`, `Integrity.lean` and the IO half of `WorkerLoop.lean`. `Tests/` covers them end to end, including the CLI itself. The proofs reason about the pure functions those layers call — which is why `step_eq_transition` and `buildShellCommand_single` matter: they pin the IO layer to the proven core.

**Serialization proofs stop at the `Json` layer.** `Roundtrip.lean` and `LockRoundtrip.lean` prove `parse ∘ serialize = id` on `Lean.Json` values. The outer string layer rests on `Json.parse ∘ Json.pretty = id`, a property of Lean's JSON library rather than of qed, and is covered by tests.
