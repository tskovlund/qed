# How to write a worker loop spec

Worker loop specs iterate: run a worker, verify criteria, feed failures back, repeat until done.

## Agent worker (Tier 1)

The simplest worker loop uses an AI agent. Provide a `prompt` and qed handles the rest:

```toml
name = "implement-feature"

[worker]
prompt = "Implement a function that parses CSV files and returns a list of records."

[[criteria]]
description = "Project compiles"
verify = { type = "command", run = "make build" }

[[criteria]]
description = "Tests pass"
verify = { type = "command", run = "make test" }
```

qed manages the prompt — on retries, it appends failure details so the agent knows what went wrong. The prompt is passed via `$QED_WORKER_PROMPT`.

Run with:

```bash
qed run implement-feature.spec.toml
```

### Custom agent command

By default, qed uses Claude CLI. To use a different agent:

```toml
[worker]
command = "my-agent --prompt"
prompt = "Implement the feature"
```

### Custom model

```toml
[worker]
prompt = "Implement the feature"
model = "claude-sonnet-4-6"
```

## Script worker (Tier 2)

For full control, omit `prompt` and provide only `command`:

```toml
[worker]
command = "./scripts/worker.sh"
```

qed runs the command as-is. Environment variables are available for optional use:

| Variable                    | Purpose                                |
| --------------------------- | -------------------------------------- |
| `$QED_WORKER_ITERATION`     | Current iteration number (1-based)     |
| `$QED_WORKER_FAILURES_FILE` | Path to JSON file with failure details |

## Controlling termination

```toml
name = "my-spec"
maxIterations = 5        # give up after 5 iterations (default: 10)
stuckThreshold = 2       # declare stuck after 2 identical failures (default: 3)

[worker]
prompt = "Fix the build"
timeout = 1800           # worker timeout in seconds (default: 3600)
```

The loop terminates when:

- All criteria pass
- The same failures repeat for `stuckThreshold` consecutive iterations (stuck)
- `maxIterations` is reached

## Working directory

```toml
[worker]
prompt = "Fix the build"
workdir = "packages/frontend"
```

The worker runs in the specified directory. Defaults to `.` (the directory where qed is invoked).
