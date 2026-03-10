[![CI](https://github.com/tskovlund/qed/actions/workflows/ci.yml/badge.svg)](https://github.com/tskovlund/qed/actions/workflows/ci.yml)
[![Lean 4](https://img.shields.io/badge/Lean-4.28.0-blue.svg)](https://lean-lang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

# qed

**AI agents are non-deterministic. Your verification shouldn't be.**

*Typed acceptance criteria. Deterministic verification. Formally proven orchestration.*

When an AI writes your code *and* your tests, passing tests prove nothing — they inherit the same blind spots as the implementation. Define what "done" means with typed specs — verified independently of the agent that did the work. Two modes:

- **Worker loop** — run a worker, verify each criterion, feed failures back, repeat until everything passes or the loop terminates. The orchestration is a formally proven state machine.
- **Verify** — run each criterion once and report results. No worker, no loop — just verification. Used for CI and standalone checks.

The core loop is written in Lean 4 with formally proven termination, stuck detection, and transition correctness. LLMs are tools used *by* the orchestrator, never the control plane.

## Example

```toml
#:schema docs/spec.schema.json
name = "state-machine"

[worker]
command = "claude -p"
prompt = "Implement the state machine transition function"

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
verify = { type = "agent", prompt = "Check: pure functions have no IO, all pattern matches are exhaustive, variable names are descriptive." }
```

The worker runs. Each criterion is verified with its typed strategy — including asking Lean's kernel to check mathematical proofs. Failures feed back to the worker. The loop terminates — guaranteed.

```bash
qed run state-machine.spec.toml
```

## Verification spectrum

| Type | Strategy | Guarantee | Status |
|------|----------|-----------|--------|
| `human` | Manual sign-off | Human judgment | ![implemented](https://img.shields.io/badge/implemented-brightgreen) |
| `agent` | Independent LLM review | Probabilistic | ![planned](https://img.shields.io/badge/planned-yellow) |
| `command` | Shell command, exit code | Deterministic | ![implemented](https://img.shields.io/badge/implemented-brightgreen) |
| `property` | Hypothesis / QuickCheck | Statistical | ![planned](https://img.shields.io/badge/planned-yellow) |
| `proof` | Lean 4 / Coq / Agda | Mathematical | ![planned](https://img.shields.io/badge/planned-yellow) |

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

**Worker loop (execution engine):**
- **Step = transition** — the loop drives the proven state machine exclusively
- **Prompt preservation** — empty failures return base prompt unchanged; failures extend, not replace
- **Shell quoting** — shellQuote wraps input correctly in single quotes

**Types, output, and parsing:**
- **Result complete partition** — every result is exactly one variant; pass/fail predicates agree with the constructor
- **Pass/fail decision correctness** — `allPassed` returns true iff no result is `.fail`
- **JSON output contract** — both verify and worker loop JSON contain their required fields
- **CI schedule parser completeness** — accepts exactly "always", "trunk", "manual"
- **TOML key integrity** — `setNested` rejects duplicate keys, `appendArray` creates correctly
- **TOML→JSON pipeline** — successful conversion implies successful parse; parse errors propagate
- **Serializer↔parser roundtrip** — parsing serialized JSON recovers the original spec exactly

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
