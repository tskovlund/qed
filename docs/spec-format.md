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

Each criterion has a description, a verification strategy, and a schedule.

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `description` | string | yes | — | Human-readable description of what this criterion verifies. |
| `schedule` | [Schedule](#schedule) | no | `"always"` | When this criterion runs. Defaults: 'always' for command/property/proof, 'local' for human, 'manual' for agent. |
| `skip` | string | no | — | Skip this criterion with the given reason. Skipped criteria show [SKIP] in output and do not affect the overall pass/fail result. |
| `verify` | [VerifyType](#verification-types) | yes | — | How to verify this criterion. Discriminated by the 'type' field. |

## Verification types

Five verification strategies, from lightweight to mathematical:

### `command`

Run a shell command and check the exit code.

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `run` | string | yes | — | Shell command to execute. |
| `timeout` | integer | no | 300 | Timeout in seconds. |
| `type` | `"command"` | yes | — |  |

### `agent`

Spawn an independent LLM agent to review against a prompt.

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `command` | string | no | — | Shell command to invoke the agent. Receives prompt via $QED_VERIFIER_PROMPT. Defaults to Claude CLI. |
| `model` | string | no | `"claude-opus-4-6"` | Model to use for the review. |
| `prompt` | string | yes | — | Review prompt for the agent. |
| `type` | `"agent"` | yes | — |  |

### `property`

Run property-based tests.

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `run` | string | yes | — | Shell command to run property tests. |
| `timeout` | integer | no | 600 | Timeout in seconds. |
| `type` | `"property"` | yes | — |  |

### `proof`

Verify a formal proof target.

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `prover` | string | yes | — | Proof system (e.g. lean4, coq, agda). |
| `target` | string | yes | — | Fully qualified name of the theorem to verify. |
| `type` | `"proof"` | yes | — |  |

### `human`

Ask a human to verify. Requires interactive stdin (schedule defaults to 'local').

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `instruction` | string | yes | — | What the human should verify. |
| `type` | `"human"` | yes | — |  |

## Schedule

Controls when a criterion runs. The runner filters by this field based on the execution context (`--ci`, `--local`, or no flag).

| Value | Description | Default for |
|-------|-------------|-------------|
| `always` | Every run — CI, pre-push, explicit | `command`, `property`, `proof` |
| `local` | Pre-push and explicit invocation — excluded from CI | `human` |
| `manual` | Only via explicit `qed run` or `qed verify` (no flags) | `agent` |

See [architecture.md](architecture.md) for the full state machine diagram and transition rules.
