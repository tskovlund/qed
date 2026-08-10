# qed

Typed spec-driven development with deterministic verification. Written in Lean 4 with formally proven core orchestration logic.

Follow the code standards in [CONVENTIONS.md](CONVENTIONS.md).

## Architecture

```
Main.lean              CLI entry point (qed run, qed verify, qed lock, qed promote, qed parse, qed version, qed help)
Qed/
  Types.lean           Core types (VerifyType, SpecMode, Spec, Spec.Pinned, LoopState, ErrorInfo)
  Shell.lean           Shell command execution and quoting utilities
  Agent.lean           Shared agent invocation (env var constants, default commands)
  Integrity.lean       Content-addressed spec integrity (SHA-256 hashing, git checks)
  Ignore.lean          .qedignore parsing and total glob matching (*, ?, [abc], [!abc], ! negation)
  ContractLock.lean    Verification contract locking (glob expansion, theorem extraction, lock file I/O)
  SpecLoader.lean      Load and pin spec files from disk (returns Spec.Pinned)
  Parser.lean          JSON spec parser (Lean.Json → Spec, parseFromJson for roundtrip proofs)
  TomlParser.lean      Pure Lean TOML parser (no external dependencies)
  TomlConverter.lean   TOML → JSON conversion (thin wrapper around TomlParser)
  TomlSerializer.lean  Spec → TOML serialization (roundtrip-proven layer + tested renderer)
  StateMachine.lean    Pure transition function (proven core)
  Verifier.lean        Verification dispatch (command, agent, property, proof)
  WorkerLoop.lean      Worker loop execution (spawn worker, verify, feed failures, repeat)
  Output.lean          Result display formatting and JSON serialization (--json flag support)
  Error.lean           Structured error formatting (code frames, location, hints)
  Serializer.lean      Spec → JSON serialization (roundtrip-proven against Parser)
Qed/Proofs/
  Termination.lean     Loop termination, progress, and fuel decrease
  StuckDetection.lean  Stuck iff same failures for stuckThreshold iterations
  NoSkip.lean          Cannot skip verification phase
  FinalStates.lean     Terminal states are absorbing
  Invariants.lean      Ready transience, phase ordering, iteration bound, lifecycle
  Monotonic.lean       Iteration count is non-decreasing
  VerifyMode.lean      Verify mode carries no worker configuration
  TypeProperties.lean  isTerminal characterization, result space partition
  OutputCorrectness.lean  allPassed correctness, JSON output contract
  ParserProperties.lean   parseSchedule completeness and rejection
  TomlProperties.lean     setNested duplicate-key rejection
  TomlJsonValidity.lean   TOML→JSON error propagation
  TomlRoundtrip.lean      TOML serializer↔parser roundtrip (toJson ∘ specToTomlPairs = specToJson)
  Roundtrip.lean          Serializer↔parser roundtrip (parseFromJson ∘ specToJson = ok)
  LockRoundtrip.lean      Lock file writer↔reader roundtrip (parseLockFileFromJson ∘ lockFileToJson = ok)
  ShellProperties.lean    shellQuote produces exactly one shell word; command-last structure
  VerifierProperties.lean Proof-target resolution and sorry detection
  IgnoreProperties.lean   Glob semantics, .qedignore parse contract, pattern precedence
  GlobProperties.lean     Valid glob patterns contain no shell metacharacters
  IntegrityEvents.lean    State machine response to the integrityViolation event
  WorkerLoopProperties.lean  step=transition, buildPrompt preserves the operator prompt
Tests/
  Main.lean            Test runner (imports all test modules)
  Types.lean           isTerminal behavior tests
  Parser.lean          JSON parser tests (all verify types, error cases)
  TomlParser.lean      TOML parser unit tests (values, tables, arrays, multi-line, non-ASCII)
  TomlSerializer.lean  TOML serializer tests (render values, render→parse roundtrips)
  Integration.lean     TOML converter and SpecLoader end-to-end tests
  Verifier.lean        Command verifier tests (shell execution, exit codes, output capture)
  ContractLock.lean    Contract lock tests (glob validation, theorem extraction, lock roundtrip)
  Ignore.lean          fnmatch glob matching and .qedignore tests (patterns, negation, parsing)
  Cli.lean             End-to-end CLI tests (invoke built binary, check output/exit codes)
specs/                 qed's own specs (dogfooding)
  build.spec.json          Build integrity — compile, test, no sorry
  cli.spec.toml            CLI + output correctness — 4 proofs + agent
  verifier.spec.toml       Verifier dispatch and shell safety — 6 proofs + agent
  worker-loop.spec.toml    Worker loop correctness — 3 proofs + agent
  state-machine.spec.toml  State machine correctness — 13 proofs + agent
  parser.spec.toml         Parser correctness — 6 proofs + agent
  verify-mode.spec.toml    Verify mode correctness — 1 proof + commands + agent
  ignore.spec.toml         .qedignore and glob correctness — 7 proofs + command + agent
  conventions.spec.toml    Convention adherence — naming, DRY, doc accuracy
  docs.spec.toml           Documentation accuracy — freshness + agent
DocGen/
  Schema.lean          JSON Schema generation (exhaustive matches on Types)
  Markdown.lean        JSON Schema → markdown transformation
  Main.lean            CLI entry point (lake exe docgen schema|markdown)
docs/                  Documentation (Diataxis: tutorial, how-to, reference, explanation)
  tutorial.md          Tutorial: write your first spec
  how-to/              How-to guides (CI, agent/human verification, worker loops, JSON vs TOML)
  cli-reference.md     CLI reference (commands, flags, exit codes, env vars, config)
  spec-format.md       Spec format reference (auto-generated from schema)
  spec.schema.json     JSON Schema (auto-generated, CI-checked)
  proven-properties.md What the proofs guarantee, by subsystem
  architecture.md      Explanation: state machine, verification dispatch, pure core/IO shell
  specs.md             Explanation: spec design philosophy and layer organization
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

- **Tier 1 (prompt present):** Agent invocation — qed manages the prompt, appends failure feedback on retries, and passes it via `$QED_WORKER_PROMPT`. Defaults to Claude CLI if no command specified.
- **Tier 2 (no prompt):** Script worker — qed runs the command as-is with env vars (`QED_WORKER_ITERATION`, `QED_WORKER_FAILURES_FILE`) available for optional use.

At least one of `command` or `prompt` must be present.

```toml
# Tier 1: agent invocation (defaults to Claude CLI)
[worker]
prompt = "Implement the feature"

# Tier 1: agent with custom command
[worker]
command = "my-agent --prompt"
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
qed                   # run the binary (.lake/build/bin on PATH via .envrc)
```

## Proven properties

The `Qed/Proofs/` directory contains 130 theorems, every one checked by Lean 4's kernel — no `sorry`, no `native_decide`. See [docs/proven-properties.md](docs/proven-properties.md) for what they guarantee.

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
