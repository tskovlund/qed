# qed

Typed spec-driven development with deterministic verification. Written in Lean 4 with formally proven core orchestration logic.

Follow the code standards in [CONVENTIONS.md](CONVENTIONS.md).

## Architecture

```
Main.lean              CLI entry point (qed run, qed parse, qed version)
Qed/
  Types.lean           Core types (VerifyType, SpecMode, Spec, LoopState)
  SpecLoader.lean      Load and list spec files from disk
  Parser.lean          JSON spec parser (Lean.Json → Spec)
  TomlConverter.lean   TOML → JSON conversion via Python's tomllib
  StateMachine.lean    Pure transition function (proven core)
  Verifier.lean        Verification dispatch (command, agent_review, property, proof)
  Output.lean          JSON result serialization
Qed/Proofs/
  Termination.lean     Loop terminates within maxIterations
  StuckDetection.lean  Stuck iff same failures for stuckThreshold iterations
  NoSkip.lean          Cannot skip verification phase
  FinalStates.lean     Terminal states are absorbing
  Monotonic.lean       Iteration count is non-decreasing
Tests/
  Main.lean            Test runner (imports all test modules)
  Types.lean           isTerminal behavior tests
  Parser.lean          JSON parser tests (all verify types, error cases)
  Integration.lean     TOML converter and SpecLoader end-to-end tests
specs/                 qed's own specs (dogfooding)
  build.spec.json      Build integrity — verify mode (no worker)
  verify-mode.spec.toml    Verify mode correctness — command + agentReview
  state-machine.spec.toml  State machine correctness — proof + agentReview
DocGen/
  Schema.lean          JSON Schema generation (exhaustive matches on Types)
  Markdown.lean        JSON Schema → markdown transformation
  Main.lean            CLI entry point (lake exe docgen schema|markdown)
docs/                  Auto-generated + hand-written documentation
  spec.schema.json     JSON Schema (auto-generated, CI-checked)
  spec-format.md       Spec format reference (auto-generated from schema)
  architecture.md      System design, state machine, mermaid diagrams
```

## Spec format

Two formats, used by context:

- **`.spec.json`** — for simple command-only specs. Parsed via `Lean.Json` (built-in, zero deps).
- **`.spec.toml`** — for specs with multi-line strings (agentReview prompts, human instructions). TOML's `"""..."""` and comments make these readable.

Both parse into the same `Spec` type. The `specs/` directory contains qed's own specs — qed verifies itself.

## Execution modes

A spec runs in one of two modes, determined by whether `worker` is present:

- **Worker loop** (`SpecMode.workerLoop`) — run the worker, verify criteria, feed failures back, repeat. Uses the state machine. `maxIterations` and `stuckThreshold` control termination.
- **Verify** (`SpecMode.verify`) — run each criterion once and report results. No state machine, no loop. Requires at least one criterion.

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
