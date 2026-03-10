# qed

Typed spec-driven development with deterministic verification. Written in Lean 4 with formally proven core orchestration logic.

Follow the code standards in [CONVENTIONS.md](CONVENTIONS.md).

## Architecture

```
Main.lean              CLI entry point (qed run, qed verify, qed parse, qed version, qed help)
Qed/
  Types.lean           Core types (VerifyType, SpecMode, Spec, LoopState)
  SpecLoader.lean      Load and list spec files from disk
  Parser.lean          JSON spec parser (Lean.Json → Spec, parseFromJson for roundtrip proofs)
  TomlParser.lean      Pure Lean TOML parser (no external dependencies)
  TomlConverter.lean   TOML → JSON conversion (thin wrapper around TomlParser)
  StateMachine.lean    Pure transition function (proven core)
  Verifier.lean        Verification dispatch (command, agent, property, proof)
  WorkerLoop.lean      Worker loop execution (spawn worker, verify, feed failures, repeat)
  Output.lean          JSON result serialization (--json flag support)
  Serializer.lean      Spec → JSON serialization (roundtrip-proven against Parser)
Qed/Proofs/
  Termination.lean     Loop termination, progress, and fuel decrease
  StuckDetection.lean  Stuck iff same failures for stuckThreshold iterations
  NoSkip.lean          Cannot skip verification phase
  FinalStates.lean     Terminal states are absorbing
  Invariants.lean      Determinism, ready transience, phase ordering, iteration bound
  Monotonic.lean       Iteration count is non-decreasing
  VerifyMode.lean      Verify mode type-level separation proofs
  TypeProperties.lean  isTerminal decidability, isPassed/isFailed characterization
  OutputCorrectness.lean  allPassed correctness, JSON output contract
  ParserProperties.lean   parseCiSchedule completeness and rejection
  TomlProperties.lean     setNested/appendArray structural integrity
  TomlJsonValidity.lean   TOML→JSON pipeline totality and error propagation
  Roundtrip.lean          Serializer↔parser roundtrip (parseFromJson ∘ specToJson = ok)
  WorkerLoopProperties.lean  step=transition, buildPrompt, shellQuote proofs
Tests/
  Main.lean            Test runner (imports all test modules)
  Types.lean           isTerminal behavior tests
  Parser.lean          JSON parser tests (all verify types, error cases)
  TomlParser.lean      TOML parser unit tests (values, tables, arrays, multi-line, non-ASCII)
  Integration.lean     TOML converter and SpecLoader end-to-end tests
  Verifier.lean        Command verifier tests (shell execution, exit codes, output capture)
  Cli.lean             End-to-end CLI tests (invoke built binary, check output/exit codes)
specs/                 qed's own specs (dogfooding)
  build.spec.json          Build integrity — compile, test, no sorry
  cli.spec.toml            CLI + output correctness — 1 proof + agent
  verifier.spec.toml       Verifier dispatch and shell execution — agent
  worker-loop.spec.toml    Worker loop correctness — 5 proofs + agent
  state-machine.spec.toml  State machine correctness — 5 proofs + agent
  parser.spec.toml         Parser correctness — 3 proofs + agent
  verify-mode.spec.toml    Verify mode correctness — 2 proofs + command + agent
  docs.spec.toml           Documentation accuracy — freshness + agent
DocGen/
  Schema.lean          JSON Schema generation (exhaustive matches on Types)
  Markdown.lean        JSON Schema → markdown transformation
  Main.lean            CLI entry point (lake exe docgen schema|markdown)
docs/                  Auto-generated + hand-written documentation
  spec.schema.json     JSON Schema (auto-generated, CI-checked)
  spec-format.md       Spec format reference (auto-generated from schema)
  architecture.md      System design, state machine, mermaid diagrams
  specs.md             Spec design philosophy and layer organization
```

## Spec format

Two formats, used by context:

- **`.spec.json`** — for simple command-only specs. Parsed via `Lean.Json` (built-in, zero deps).
- **`.spec.toml`** — for specs with multi-line strings (agent prompts, human instructions). TOML's `"""..."""` and comments make these readable.

Both parse into the same `Spec` type. The `specs/` directory contains qed's own specs — qed verifies itself.

## Execution modes

A spec runs in one of two modes, determined by whether `worker` is present:

- **Worker loop** (`SpecMode.workerLoop`) — run the worker, verify criteria, feed failures back, repeat. Uses the state machine. `maxIterations` and `stuckThreshold` control termination.
- **Verify** (`SpecMode.verify`) — run each criterion once and report results. No state machine, no loop. Requires at least one criterion.

## Worker configuration

Two tiers:

- **Tier 1 (prompt present):** qed manages the prompt. On retries, failure feedback is appended. The command receives the full prompt via `$QED_PROMPT` env var and qed runs `{command} "$QED_PROMPT"` through the shell.
- **Tier 2 (no prompt):** full control. qed runs the command as-is with env vars (`QED_ITERATION`, `QED_FAILURES_FILE`) available for optional use.

```toml
# Tier 1: qed manages the prompt
[worker]
command = "claude -p"
prompt = "Implement the feature"

# Tier 2: full control
[worker]
command = "./scripts/worker.sh"
```

## Key design principle

The worker loop orchestrator is a **deterministic state machine**. LLMs are tools used by the orchestrator (as workers and reviewers), never the control plane. The pure transition function (`Qed.StateMachine.transition`) has no IO — all proofs reason about this function.

Specs are **files in the repo** — JSON or TOML, version-controlled, schema-validated. `SpecLoader` handles reading and listing spec files from disk.

## Dev environment

Devbox + elan. Devbox provides elan (Lean version manager) via Nix. The `lean-toolchain` file pins the exact Lean version.

```bash
direnv allow          # or: devbox shell
```

First run downloads the Lean toolchain via elan (~500MB). Subsequent runs are instant.

## Commands

```bash
devbox run build      # lake build
devbox run test       # lake test
devbox run check      # build + test
```

Or directly (inside devbox shell / after direnv allow):

```bash
lake build            # build the qed binary
lake test             # run tests
.lake/build/bin/qed   # run the binary
```

## Proven properties

The `Qed/Proofs/` directory contains formal proofs verified by Lean 4's kernel. All proofs are complete (no `sorry`).

**State machine (worker loop):**

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

**Worker loop (execution engine):**

| File | Theorem | Property |
|------|---------|----------|
| `WorkerLoopProperties.lean` | `step_eq_transition` | The loop's step function is exactly StateMachine.transition |
| `WorkerLoopProperties.lean` | `buildPrompt_empty_failures` | No failures → base prompt returned unchanged |
| `WorkerLoopProperties.lean` | `buildPrompt_nonempty_appends` | Failures → base prompt is extended (not replaced) |
| `WorkerLoopProperties.lean` | `shellQuote_wraps` | shellQuote wraps input in single quotes |
| `WorkerLoopProperties.lean` | `shellQuote_empty` | shellQuote of "" produces "''" |

**Types, output, parser, and TOML parser:**

| File | Theorem | Property |
|------|---------|----------|
| `TypeProperties.lean` | `isTerminal_decidable` | Every LoopState is either terminal or not |
| `TypeProperties.lean` | `result_complete_partition` | Every VerificationResult is exactly one variant; isPassed/isFailed predicates agree with the constructor |
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

## Repo-specific conventions

- **`autoImplicit` is off** — all variables must be explicitly declared. Avoids surprises in theorem proving
- **Pure core, IO shell** — the state machine transition function is pure. IO (process spawning, file reading, JSON output) lives in `Main.lean` and `Verifier.lean`
- **No `sorry`** — proofs must be complete. `sorry` is a placeholder that marks unfinished proofs; CI rejects any `sorry` in `Qed/Proofs/`
- **Tests cover behavior, proofs cover properties** — tests verify that the CLI works end-to-end; proofs verify that the state machine has the right mathematical properties

## Git workflow

### PR workflow

1. Create feature branch
2. Make changes, test with `lake build` and `lake test`
3. Push and create PR
4. Review loop: wait for CI + Copilot -> address comments -> push -> iterate until clean
5. Merge

### Issue tracking

GitHub Issues for implementation tracking. Linear for higher-level planning (workspace: tskovlund, project: qed).

**Templates:** Enhancement, Bug, Research. Use the appropriate template. Blank issues disabled.

**Labels:** `bug`, `enhancement`, `documentation`, `research`, `dependencies`, `github actions`, `spec`
