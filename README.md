[![CI](https://github.com/tskovlund/qed/actions/workflows/ci.yml/badge.svg)](https://github.com/tskovlund/qed/actions/workflows/ci.yml)
[![Lean 4](https://img.shields.io/badge/Lean-4.28.0-blue.svg)](https://lean-lang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

# qed

**Typed acceptance criteria. Deterministic verification. Formally proven orchestration.**

Define what "done" means with typed specs. Two modes:

- **Worker loop** — run a worker, verify each criterion, feed failures back, repeat until everything passes or the loop terminates. The orchestration is a formally proven state machine.
- **Verify** — run each criterion once and report results. No worker, no loop — just verification. Used for CI and standalone checks.

The core loop is written in Lean 4 with formally proven termination, stuck detection, and transition correctness. LLMs are tools used *by* the orchestrator, never the control plane.

## Example

```toml
#:schema docs/spec.schema.json
name = "state-machine"

[worker]
command = "claude -p 'implement the state machine transition function'"

[[criteria]]
description = "Project builds and tests pass"
verify = { type = "command", run = "lake build && lake test" }

[[criteria]]
description = "Transition function terminates within maxIterations"
verify = { type = "proof", prover = "lean4", target = "Qed.Proofs.Termination.transitionTerminates" }

[[criteria]]
description = "Terminal states are absorbing — no further transitions"
verify = { type = "proof", prover = "lean4", target = "Qed.Proofs.FinalStates.terminalStatesAbsorbing" }

[[criteria]]
description = "Code follows conventions and handles edge cases"
verify = { type = "agentReview", prompt = "Check: pure functions have no IO, all pattern matches are exhaustive, variable names are descriptive." }
```

The worker runs. Each criterion is verified with its typed strategy — including asking Lean's kernel to check mathematical proofs. Failures feed back to the worker. The loop terminates — guaranteed.

```bash
qed run state-machine.spec.toml
```

## Verification spectrum

| Type | Strategy | Guarantee |
|------|----------|-----------|
| `human` | Manual sign-off | Human judgment |
| `agentReview` | Independent LLM review | Probabilistic |
| `command` | Shell command, exit code | Deterministic |
| `property` | Hypothesis / QuickCheck | Statistical |
| `proof` | Lean 4 / Coq / Agda | Mathematical |

## Proven properties

Formal proofs verified by Lean 4's kernel:

**State machine (worker loop):**
- **Termination** — the loop always reaches a terminal state within maxIterations
- **Stuck detection** — fires iff the same failures repeat consecutively
- **No skipped verification** — worker output is always checked before passing
- **Worker before verification** — verifying is only reachable from workerRunning
- **Terminal states are absorbing** — once done, done
- **Monotonic iteration count** — no going backwards

**Verify mode:**
- **No worker or loop config** — verify mode cannot carry worker loop state
- **Independent of state machine** — verify mode does not use the transition function

## Status

Under active development — building the MVP. qed eats its own dogfood: the repo's own acceptance criteria are defined as [specs](specs/).

## Quick start

```bash
devbox shell          # or: direnv allow
lake build            # build
lake test             # test
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for full setup instructions.

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture](docs/architecture.md) | Execution modes, state machine, verification dispatch |
| [Spec design](docs/specs.md) | Why these specs exist and how they're organized |
| [Spec format](docs/spec-format.md) | Complete reference for spec files (auto-generated) |
| [JSON Schema](docs/spec.schema.json) | Machine-readable schema for editor autocomplete |

## Author

Thomas Skovlund Hansen — [skovlund.dev](https://skovlund.dev) · [thomas@skovlund.dev](mailto:thomas@skovlund.dev)

## License

[MIT](LICENSE)
