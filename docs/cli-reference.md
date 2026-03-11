# CLI Reference

> Configuration, environment variables, exit codes, and internal constants.

## Commands

```
qed run <spec-file>       Run verification (verify mode) or worker loop
qed verify [spec-or-dir]  Verify a spec file, or all specs in a directory (recursive)
                          Defaults to current directory if omitted
qed parse <spec-file>     Parse and validate a spec file
qed version               Print version
qed help                  Show this help
```

## CLI flags

| Flag      | Purpose                                                                 |
| --------- | ----------------------------------------------------------------------- |
| `--json`  | Machine-readable JSON output (position-independent)                     |
| `--local` | Local mode — excludes `manual` criteria only (position-independent)     |
| `--ci`    | CI mode — excludes `manual` and `local` criteria (position-independent) |

## Exit codes

| Code | Meaning                                                                |
| ---- | ---------------------------------------------------------------------- |
| 0    | Success — all criteria passed                                          |
| 1    | Verification failure — one or more criteria failed                     |
| 2    | Configuration or usage error — bad spec, missing file, unknown command |

## Configuration

All meaningful parameters are configurable at the spec level — defaults are sensible but overridable:

| Parameter            | Default           | Where set                  |
| -------------------- | ----------------- | -------------------------- |
| `maxIterations`      | 10                | Spec file (worker loop)    |
| `stuckThreshold`     | 3                 | Spec file (worker loop)    |
| `timeout` (worker)   | 3600s             | Spec file (`[worker]`)     |
| `timeout` (command)  | 300s              | Spec file (`[[criteria]]`) |
| `timeout` (property) | 600s              | Spec file (`[[criteria]]`) |
| `model` (agent)      | `claude-opus-4-6` | Spec file (`[[criteria]]`) |
| `workdir`            | `.`               | Spec file (`[worker]`)     |

## Environment variables

### Consumed by qed

| Variable | Purpose                                                 |
| -------- | ------------------------------------------------------- |
| `TMPDIR` | Temp directory for failure files (falls back to `/tmp`) |

### Set by qed for workers

| Variable                   | Purpose                                         |
| -------------------------- | ----------------------------------------------- |
| `QED_WORKER_PROMPT`        | Full prompt with failure feedback (Tier 1 only) |
| `QED_WORKER_ITERATION`     | Current iteration number                        |
| `QED_WORKER_FAILURES_FILE` | Path to JSON file with failure details          |

### Set by qed for agent verification

| Variable                     | Purpose                                                              |
| ---------------------------- | -------------------------------------------------------------------- |
| `QED_VERIFIER_PROMPT`        | The criterion's review prompt                                        |
| `QED_VERIFIER_SYSTEM_PROMPT` | Verdict format instructions (JSON block with `{"pass": true/false}`) |

## Named constants

Not configurable — reasonable defaults hardcoded in the IO shell:

| Constant              | Value      | Location                                         |
| --------------------- | ---------- | ------------------------------------------------ |
| `maxOutputLength`     | 2000 chars | `Verifier.lean` — output truncation (keeps tail) |
| `stderrPreviewLength` | 200 chars  | `WorkerLoop.lean` — stderr preview in terminal   |
