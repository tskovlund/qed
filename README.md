[![CI](https://github.com/tskovlund/qed/actions/workflows/ci.yml/badge.svg)](https://github.com/tskovlund/qed/actions/workflows/ci.yml)
[![Lean 4](https://img.shields.io/badge/Lean-4.28.0-blue.svg)](https://lean-lang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

# qed

**Typed acceptance criteria. Deterministic verification. Formally proven orchestration.**

Define what "done" means with typed specs. qed runs a worker, verifies each criterion using the right strategy — from shell commands to formal proofs — and loops until everything passes or it knows to stop.

The core loop is a state machine written in Lean 4 with formally proven termination, stuck detection, and transition correctness. LLMs are tools used *by* the orchestrator, never the control plane.

## Example

```json
{
  "name": "add-auth",
  "worker": { "command": "claude -p 'implement auth middleware'" },
  "criteria": [
    {
      "description": "All tests pass",
      "verify": { "type": "command", "run": "make test" }
    },
    {
      "description": "No credentials in source",
      "verify": { "type": "command", "run": "! grep -r 'password' src/" }
    },
    {
      "description": "Auth flow handles edge cases",
      "verify": {
        "type": "agentReview",
        "prompt": "Review the auth middleware. Check: expired tokens, missing headers, concurrent sessions."
      }
    }
  ]
}
```

```bash
qed run spec.json
```

The worker runs. Each criterion is verified with its typed strategy. Failures feed back to the worker. The loop terminates — guaranteed.

## Verification spectrum

| Type | Strategy | Guarantee |
|------|----------|-----------|
| `command` | Shell command, exit code | Deterministic |
| `agentReview` | Independent LLM review | Probabilistic |
| `property` | Hypothesis / QuickCheck | Probabilistic |
| `proof` | Lean 4 / Coq / Agda | Mathematical |
| `human` | Manual sign-off | Human judgment |

## Proven properties

The state machine has formal proofs verified by Lean 4's kernel:

- **Termination** — the loop always reaches a terminal state
- **Stuck detection** — fires iff the same failures repeat consecutively
- **No skipped verification** — worker output is always checked before passing
- **Terminal states are absorbing** — once done, done
- **Monotonic iteration count** — no going backwards

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
| [Architecture](docs/architecture.md) | State machine, verification dispatch, backend design |
| [Spec format](docs/spec-format.md) | Complete reference for spec files (auto-generated) |
| [JSON Schema](docs/spec.schema.json) | Machine-readable schema for editor autocomplete |

## Author

Thomas Skovlund Hansen — [skovlund.dev](https://skovlund.dev) · [thomas@skovlund.dev](mailto:thomas@skovlund.dev)

## License

[MIT](LICENSE)
