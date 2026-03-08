# qed

Typed spec-driven development with deterministic verification — from shell commands to formal proofs.

Define acceptance criteria per task. Dispatch typed verification. Loop deterministically until all criteria pass or escalate. Core orchestration logic is formally verified in Lean 4.

## The verification spectrum

| Level | Type           | Guarantee        | Example                                |
|-------|----------------|------------------|----------------------------------------|
| 0     | `human`        | Human judgment   | "Visual change looks correct"          |
| 1     | `command`      | Exit code        | `make test`, `make lint`               |
| 2     | `agent_review` | LLM evaluation   | "Check diff follows CONVENTIONS.md"    |
| 3     | `property`     | Probabilistic    | Hypothesis / QuickCheck properties     |
| 4     | `proof`        | Mathematical     | Lean 4 theorem                         |

## Quick start

```bash
# Install
lake build

# Define a spec
cat > spec.json << 'EOF'
{
  "name": "my-task",
  "worker": {
    "command": "claude -p 'implement the feature' --output-format json"
  },
  "criteria": [
    {
      "description": "All tests pass",
      "verify": { "type": "command", "run": "make test" }
    },
    {
      "description": "No lint violations",
      "verify": { "type": "command", "run": "make lint" }
    }
  ]
}
EOF

# Run the loop
qed run spec.json
```

## How it works

```
Spec File (JSON) ──► qed run ──► Deterministic Loop
                                       │
                         Worker ◄── dispatch ──► Verifiers
                       (claude/cmd)              (command/agent/proof)
                                       │
                                  All pass? ──► QED
                                  Stuck?    ──► Escalate
```

1. **Parse** the spec file — typed acceptance criteria with verification strategy per criterion
2. **Dispatch** the worker — any shell command (Claude Code, scripts, builds)
3. **Verify** each AC — run the typed verifier (shell command, agent review, property test, formal proof)
4. **Loop** — feed failures back to the worker, repeat until all pass
5. **Terminate** — hard cap on iterations + stuck detection (same failures for N consecutive rounds)

The orchestrator is a deterministic state machine. LLMs are tools used **by** the orchestrator (as workers and reviewers), not the control plane. Core loop logic — state transitions, termination, stuck detection — is formally proven in Lean 4.

## Architecture

```
qed/
  Main.lean              CLI entry point
  Qed/
    Types.lean           Core types (AC spec, verification types, loop state)
    Parser.lean          JSON spec parser
    StateMachine.lean    Pure transition function (the proven core)
    Verifier.lean        Verification dispatch (command, agent, proof)
    Output.lean          JSON result output
  Qed/Proofs/
    Termination.lean     Loop always terminates
    StuckDetection.lean  Stuck iff same failures for N iterations
    NoSkip.lean          Cannot skip verification
    FinalStates.lean     Terminal states are final
    Monotonic.lean       Iteration count never decreases
  Tests/
    Main.lean            Test driver
```

## Proven properties

The core state machine has formal proofs (verified by Lean 4's kernel) for:

1. **Termination** — the loop always reaches a terminal state within `maxIterations`
2. **Stuck detection correctness** — `stuck` iff the same failures persist for `stuckThreshold` consecutive iterations
3. **No skipped verification** — cannot transition from worker to passed without verifying
4. **Terminal states are final** — once passed/stuck/escalated, no further transitions
5. **Monotonic iteration count** — iteration count never decreases

## Status

**Under active development.** Building the MVP — see the [Linear project](https://linear.app/tskovlund/project/qed-bd1192dc905e) for progress.

qed is built using qed — the repo's own acceptance criteria are defined in [`qed.spec.json`](qed.spec.json).

## Development

```bash
devbox shell          # or: direnv allow
lake build            # build the binary
lake test             # run tests
devbox run check      # build + test
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for full setup instructions.

## Author

Thomas Skovlund Hansen — [skovlund.dev](https://skovlund.dev)

## License

[MIT](LICENSE)
