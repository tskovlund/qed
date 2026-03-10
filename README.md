[![CI](https://github.com/tskovlund/qed/actions/workflows/ci.yml/badge.svg)](https://github.com/tskovlund/qed/actions/workflows/ci.yml)
[![Lean 4](https://img.shields.io/badge/Lean-4.28.0-blue.svg)](https://lean-lang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

# qed

*Typed acceptance criteria. Deterministic verification. Formally proven orchestration.*

**AI agents are non-deterministic. Your verification shouldn't be.**

When an AI writes your code *and* your tests, passing tests prove nothing — they inherit the same blind spots as the implementation. qed defines what "done" means with typed specs — verified independently of the agent that did the work.

```toml
name = "state-machine"

[worker]
prompt = "Implement the state machine transition function"

[[criteria]]
description = "Project builds and tests pass"
verify = { type = "command", run = "lake build && lake test" }

[[criteria]]
description = "Transition function terminates within maxIterations"
verify = { type = "proof", prover = "lean4", target = "Proofs.Termination.loop_terminates" }

[[criteria]]
description = "Code follows conventions and handles edge cases"
verify = { type = "agent", prompt = "Review for exhaustive matches, pure functions, and naming." }
```

The worker runs. Each criterion is verified with its typed strategy — a shell command checks the build, Lean's kernel checks the proof, an independent LLM reviews the design. Failures feed back to the worker. The loop terminates — guaranteed.

```
$ qed run state-machine.spec.toml

── Iteration 1 ──
  Running worker...
  Verifying criteria...
    [✓] Project builds and tests pass
    [✗] Transition function terminates within maxIterations
    [✓] Code follows conventions and handles edge cases
  1 criteria failed, retrying...

── Iteration 2 ──
  Running worker...
  Verifying criteria...
    [✓] Project builds and tests pass
    [✓] Transition function terminates within maxIterations
    [✓] Code follows conventions and handles edge cases

All criteria passed after 2 iteration(s).
```

## Two modes

- **Worker loop** — run a worker, verify, feed failures back, repeat. The orchestration is a formally proven state machine with guaranteed termination and stuck detection.
- **Verify** — run each criterion once and report. No worker, no loop. For CI and standalone checks.

## Verification spectrum

Five verification types, from human judgment to mathematical proof:

| Type | Strategy | Guarantee | Status |
|------|----------|-----------|--------|
| `human` | Manual sign-off | Human judgment | ![implemented](https://img.shields.io/badge/implemented-brightgreen) |
| `agent` | Independent LLM review | Probabilistic | ![implemented](https://img.shields.io/badge/implemented-brightgreen) |
| `command` | Shell command, exit code | Deterministic | ![implemented](https://img.shields.io/badge/implemented-brightgreen) |
| `property` | Hypothesis / QuickCheck | Statistical | ![planned](https://img.shields.io/badge/planned-yellow) |
| `proof` | Lean 4 / Coq / Agda | Mathematical | ![planned](https://img.shields.io/badge/planned-yellow) |

## Formally proven

The core is written in Lean 4 with complete formal proofs — no `sorry`, no gaps. Key guarantees:

- **Termination** — the loop always reaches a terminal state within `maxIterations`
- **Stuck detection** — fires iff the same failures repeat for `stuckThreshold` consecutive iterations
- **No skipped verification** — worker output is always checked before reaching a success state
- **Absorbing terminal states** — once done, done — no event can change a terminal state
- **Serializer↔parser roundtrip** — parsing serialized JSON recovers the original spec exactly

40+ theorems total across state machine, worker loop, types, output, parsing, and TOML. See [proven properties](docs/proven-properties.md) for the full list.

## Status

Under active development — building the MVP. qed eats its own dogfood: the repo's own acceptance criteria are defined as [specs](specs/) and verified in CI on every push.

## Quick start

```bash
devbox shell          # or: direnv allow
lake build            # build
lake test             # test
qed verify specs/     # verify qed's own specs
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for full setup instructions.

## Documentation

**Start here:** [Tutorial](docs/tutorial.md) — write your first spec in 5 minutes.

**How-to guides:**
[Add qed to CI](docs/how-to/ci.md) ·
[Agent verification](docs/how-to/agent-verification.md) ·
[Worker loop specs](docs/how-to/worker-loop.md) ·
[JSON vs TOML](docs/how-to/json-vs-toml.md)

**Reference:**
[Spec format](docs/spec-format.md) ·
[CLI reference](docs/cli-reference.md) ·
[Proven properties](docs/proven-properties.md) ·
[JSON Schema](docs/spec.schema.json)

**Explanation:**
[Architecture](docs/architecture.md) ·
[Spec design](docs/specs.md)

## Author

Thomas Skovlund Hansen — [skovlund.dev](https://skovlund.dev) · [thomas@skovlund.dev](mailto:thomas@skovlund.dev)

## License

[MIT](LICENSE)
