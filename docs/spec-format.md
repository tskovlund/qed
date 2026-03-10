# Spec Format Reference

> **Auto-generated** from the Lean types in [`Qed/Types.lean`](../Qed/Types.lean) via JSON Schema.
> Do not edit — run `devbox run docs` to regenerate.

Specs are written in JSON (`.spec.json`) or TOML (`.spec.toml`). Both formats parse into the same types. Use JSON for simple specs, TOML when you need multi-line strings (agent review prompts, human instructions).

Schema: [`spec.schema.json`](spec.schema.json) — add `"$schema": "docs/spec.schema.json"` (JSON) or `#:schema docs/spec.schema.json` (TOML) for editor autocomplete.

## Structure

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `criteria` | [Criterion](#criterion)[] | yes | — | Acceptance criteria — each verified independently. |
| `maxIterations` | integer | no | 10 | Maximum worker iterations before giving up. Only valid when worker is present. |
| `name` | string | yes | — | Unique identifier for this spec. |
| `stuckThreshold` | integer | no | 3 | Consecutive identical failures before declaring stuck. Only valid when worker is present. |
| `worker` | [Worker](#worker) | no | — | Configuration for the worker. If present, qed runs in worker loop mode (iterate until criteria pass). If absent, qed runs in verify mode (single-pass verification). At least one of 'command' or 'prompt' is required. |

## Execution modes

A spec runs in one of two modes, determined by whether `worker` is present:

- **Worker loop** (`worker` present) — run the worker, verify criteria, feed failures back, repeat until all pass or the loop terminates (stuck / max iterations).
- **Verify** (`worker` absent) — run each criterion once and report results. Requires at least one criterion. Used for CI checks and standalone verification.

`maxIterations` and `stuckThreshold` only apply in worker loop mode.

## Worker

Optional. If present, qed runs in worker loop mode. The worker is the command that attempts to satisfy the criteria — an AI agent, a build command, a script, anything with a shell interface.

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `command` | string | no | — | Shell command to run the worker. For agent workers (prompt present), defaults to Claude CLI. For script workers (no prompt), required. The command receives the prompt via $QED_WORKER_PROMPT env var. |
| `model` | string | no | `"claude-opus-4-6"` | Model to use for agent workers. Only used when prompt is present. |
| `prompt` | string | no | — | Prompt for the worker agent. When present, this is agent invocation — qed manages the prompt (appends failure feedback on retries) and passes it via $QED_WORKER_PROMPT env var. When absent, the command has full control (script worker). |
| `timeout` | integer | no | 3600 | Worker timeout in seconds. |
| `workdir` | string | no | `"."` | Working directory for the worker. |

## Criterion

Each criterion has a description, a verification strategy, and a CI schedule.

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `ci` | [CiSchedule](#ci-schedule) | no | `"always"` | When this criterion runs in CI. Defaults: 'always' for automatable types, 'manual' for human. |
| `description` | string | yes | — | Human-readable description of what this criterion verifies. |
| `verify` | [VerifyType](#verification-types) | yes | — | How to verify this criterion. Discriminated by the 'type' field. |

## Verification types

Five verification strategies, from lightweight to mathematical:

### `command`

Run a shell command and check the exit code.

| Field | Type | Required | Default |
|-------|------|----------|---------|
| `run` | string | yes | — |
| `timeout` | integer | no | 300 |
| `type` | `"command"` | yes | — |

### `agent`

Spawn an independent LLM agent to review against a prompt.

| Field | Type | Required | Default |
|-------|------|----------|---------|
| `command` | string | no | — |
| `model` | string | no | `"claude-opus-4-6"` |
| `prompt` | string | yes | — |
| `type` | `"agent"` | yes | — |

### `property`

Run property-based tests.

| Field | Type | Required | Default |
|-------|------|----------|---------|
| `run` | string | yes | — |
| `timeout` | integer | no | 600 |
| `type` | `"property"` | yes | — |

### `proof`

Verify a formal proof target.

| Field | Type | Required | Default |
|-------|------|----------|---------|
| `prover` | string | yes | — |
| `target` | string | yes | — |
| `type` | `"proof"` | yes | — |

### `human`

Ask a human to verify. Cannot run in CI (ci defaults to 'manual').

| Field | Type | Required | Default |
|-------|------|----------|---------|
| `instruction` | string | yes | — |
| `type` | `"human"` | yes | — |

## CI schedule

Controls when a criterion runs in CI. The runner filters by this field — no special-casing of verification types.

| Value | Description | Default for |
|-------|-------------|-------------|
| `always` | Every CI run (PRs, pushes, merge queue) | all automatable types |
| `trunk` | Only when the default branch changes | — |
| `manual` | Only via explicit `qed run` | `human` |

See [architecture.md](architecture.md) for the full state machine diagram and transition rules.
