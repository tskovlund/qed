# Architecture

> How qed works internally — execution modes, the state machine, and verification dispatch.

## Overview

qed has two execution modes, determined by the `SpecMode` type:

### Worker loop (`SpecMode.workerLoop`)

When a spec has a `worker`, qed runs an iterative loop:

1. Dispatches the **worker** (any shell command — an AI agent, a build script, etc.)
2. **Verifies** each criterion using its typed strategy
3. **Loops** until all criteria pass, or terminates (stuck, max iterations, escalation)

The orchestrator is a **deterministic state machine**. LLMs are tools used *by* the orchestrator (as workers and reviewers), never the control plane.

### Verify (`SpecMode.verify`)

When a spec has no `worker`, qed runs each criterion once and reports results. No loop, no state machine — just a `List AcceptanceCriterion → List VerificationResult` function. Used for CI checks and standalone verification. Requires at least one criterion.

## State machine (worker loop)

The worker loop is driven by a pure transition function with no IO:

```lean
def transition (config : LoopConfig) (state : LoopState) (context : LoopContext)
    (event : LoopEvent) : LoopState × LoopContext
```

All proofs reason about this function. IO (process spawning, file reading) lives in the outer shell.

### State diagram

```mermaid
stateDiagram-v2
    [*] --> ready

    ready --> workerRunning : start

    workerRunning --> verifying : workerDone

    verifying --> passed : allPassed
    verifying --> workerRunning : someFailed\n[n < max ∧ not stuck]
    verifying --> stuck : someFailed\n[same failures ≥ stuckThreshold]
    verifying --> maxIterationsReached : someFailed\n[n ≥ maxIterations]

    passed --> [*]
    stuck --> [*]
    maxIterationsReached --> [*]
    escalated --> [*]
```

### Events

| Event | Description |
|-------|-------------|
| `workerDone` | Worker has completed its run |
| `allPassed` | All auto-verifiable criteria passed |
| `someFailed` | Some criteria failed (carries the failing descriptions) |
| `escalate` | External request for human intervention |

### Terminal states

Terminal states are **absorbing** — once reached, all events are ignored. This is formally proven in `Qed/Proofs/FinalStates.lean`.

| State | Meaning |
|-------|---------|
| `passed` | All criteria satisfied |
| `stuck` | Same failures repeated for `stuckThreshold` consecutive iterations |
| `maxIterationsReached` | Hit the iteration cap |
| `escalated` | Escalated for human intervention |

### Stuck detection

The loop tracks consecutive identical failures via `LoopContext`:

```lean
structure LoopContext where
  consecutiveFailureCount : Nat
  previousFailures : List String
```

On each `someFailed` event, the transition function compares the current failures to the previous ones. If they match, the consecutive count increments. If they differ, it resets to 1. When the count reaches `stuckThreshold`, the loop enters `stuck`.

This prevents infinite retry loops where the worker keeps producing the same broken output.

## Verification dispatch

Each acceptance criterion has a typed verification strategy:

```mermaid
flowchart LR
    criterion --> verify{verify type}
    verify -->|human| human[Human judgment\nmanual sign-off]
    verify -->|agentReview| agent[LLM agent\nprompt-based review]
    verify -->|command| shell[Shell command\nexit code check]
    verify -->|property| prop[Property tests\nHypothesis / QuickCheck]
    verify -->|proof| prover[Formal proof\nLean 4 / Coq / Agda]
```

The verification type determines both **what runs** and **what guarantee you get**:

| Type | Runs | Guarantee | CI default |
|------|------|-----------|------------|
| `human` | Nothing (waits) | Human judgment | `manual` |
| `agentReview` | LLM agent | Probabilistic | `always` |
| `command` | Shell command | Deterministic | `always` |
| `property` | Test framework | Statistical | `always` |
| `proof` | Proof checker | Mathematical | `always` |

## Spec loading

Specs are files in the repo — version-controlled, schema-validated, colocated with the code they specify. `SpecLoader` reads and lists spec files from disk:

```lean
def loadSpec (path : System.FilePath) : IO (Except String Spec)
def listSpecs (directory : System.FilePath) (extension : String) : IO (Except String (List System.FilePath))
```

## Pure core, IO shell

The architecture follows a strict separation:

| Layer | IO? | What lives here |
|-------|-----|-----------------|
| **Pure core** | No | Types, StateMachine, Proofs |
| **IO shell** | Yes | Parser, Verifier, SpecLoader, CLI |

The pure core is where all proofs live. It has no side effects, no process spawning, no file access. The IO shell wraps the pure core with real-world effects — parsing files, running commands, reporting results.

This separation means proofs about the state machine are proofs about the actual system behavior, not about a model of it.

## Spec format

Two serialization formats, same types:

- **JSON** (`.spec.json`) — simple specs, parsed via `Lean.Json`
- **TOML** (`.spec.toml`) — multi-line strings (agent prompts, human instructions)

Both validate against the same [JSON Schema](spec.schema.json). See [spec-format.md](spec-format.md) for the full reference.
