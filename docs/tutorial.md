# Tutorial: Write your first spec

> A step-by-step walkthrough from zero to a working qed spec.

By the end of this tutorial you'll have written a spec that verifies a shell command, reviewed code with an AI agent, and seen qed's output format.

## Prerequisites

- qed installed and on your PATH (see [CONTRIBUTING.md](../CONTRIBUTING.md) for setup)
- A project directory to work in

## Step 1: A minimal spec

Create a file called `hello.spec.toml`:

```toml
name = "hello"

[[criteria]]
description = "echo succeeds"
verify = { type = "command", run = "echo hello" }
```

This is the simplest possible spec: one criterion, verified by running a shell command and checking the exit code.

Run it:

```bash
qed verify hello.spec.toml
```

You should see:

```
Verifying hello...
  [✓] echo succeeds

All 1 criteria passed.
```

## Step 2: A failing criterion

Add a second criterion that fails:

```toml
name = "hello"

[[criteria]]
description = "echo succeeds"
verify = { type = "command", run = "echo hello" }

[[criteria]]
description = "this will fail"
verify = { type = "command", run = "false" }
```

Run it again:

```bash
qed verify hello.spec.toml
```

```
Verifying hello...
  [✓] echo succeeds
  [✗] this will fail

1 of 2 criteria failed.
```

qed exits with code 1 when any criterion fails. This makes it easy to use in CI — a non-zero exit fails the pipeline.

## Step 3: JSON output

Add `--json` for machine-readable output:

```bash
qed verify hello.spec.toml --json
```

```json
{"spec":"hello","passed":false,"criteria":[{"description":"echo succeeds","result":"pass","details":"hello"},{"description":"this will fail","result":"fail","details":"exit code 1\n"}]}
```

The `--json` flag is position-independent — it works before or after the spec path.

## Step 4: Add an agent criterion

Remove the failing criterion and add an agent review. Agent criteria use an LLM to review code against a prompt:

```toml
name = "hello"

[[criteria]]
description = "echo succeeds"
verify = { type = "command", run = "echo hello" }

[[criteria]]
description = "README exists and is well-written"
verify = { type = "agent", prompt = "Check that README.md exists, has a clear title, and describes what the project does." }
```

Run it:

```bash
qed verify hello.spec.toml
```

The agent criterion spawns Claude (or your configured agent command) to review the codebase. If Claude isn't available, the criterion is skipped with a message.

## Step 5: Verify a directory

qed can verify all specs in a directory recursively:

```bash
qed verify specs/
```

This finds all `.spec.json` and `.spec.toml` files, skipping hidden directories and build artifacts. With no argument, `qed verify` defaults to the current directory.

## Step 6: A worker loop spec

So far we've used **verify mode** — run each criterion once and report. For iterative development with an AI agent, use **worker loop mode** by adding a `[worker]`:

```toml
name = "implement-greeting"

[worker]
prompt = "Create a file called greeting.sh that prints 'Hello, world!'"

[[criteria]]
description = "greeting.sh prints the expected output"
verify = { type = "command", run = "bash greeting.sh | grep 'Hello, world!'" }
```

Run it with `qed run`:

```bash
qed run implement-greeting.spec.toml
```

qed dispatches the worker (an AI agent by default), then verifies the criteria. If any criterion fails, the failures are fed back to the worker and it tries again. The loop continues until all criteria pass, the worker gets stuck (same failures repeating), or `maxIterations` is reached.

## What's next

- [Spec format reference](spec-format.md) — all fields, types, and defaults
- [Architecture](architecture.md) — how the state machine and verification dispatch work
- [How-to guides](how-to/) — recipes for specific tasks (CI integration, custom workers, etc.)
