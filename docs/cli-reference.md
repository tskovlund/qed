# CLI Reference

> Configuration, environment variables, exit codes, and internal constants.

## Commands

```
qed run <spec-file>       Run verification (verify mode) or worker loop
qed verify [spec-or-dir]  Verify a spec file, or all specs in a directory (recursive)
                          Defaults to current directory if omitted
qed lock [directory]      Generate or update qed.lock from specs (defaults to current dir)
qed promote <spec-file>   Promote a worker loop spec to verify mode (strip worker section)
qed parse <spec-file>     Parse and validate a spec file
qed version               Print version
qed help                  Show this help
```

## CLI flags

| Flag           | Purpose                                                                        |
| -------------- | ------------------------------------------------------------------------------ |
| `--json`       | Machine-readable JSON output (position-independent)                            |
| `--json-lines` | Stream results as JSON Lines (one compact JSON object per line)                |
| `--auto`       | Skip heavy and manual criteria (auto-detected when `CI=true`)                  |
| `--extended`   | Include heavy criteria, skip manual (for thorough CI runs)                     |
| `--full`       | Run all criteria including manual (overrides CI auto-detection)                |
| `--pin`        | Require spec files to match their git-committed version (position-independent) |
| `--no-lock`    | Skip contract lock verification during worker loop                             |
| `--output`     | Output file path for `promote` command                                         |
| `--archive`    | Move original spec to `archive/` directory after promoting                     |

## Schedule filtering

Each criterion has a `schedule` value describing its nature. Flags control which schedules run:

|                                | `always` | `heavy`  | `manual` |
| ------------------------------ | -------- | -------- | -------- |
| `--auto` / no flag (`CI=true`) | **runs** | skipped  | skipped  |
| `--extended`                   | **runs** | **runs** | skipped  |
| `--full` / no flag (local)     | **runs** | **runs** | **runs** |

Schedule defaults: `always` for command/property/proof, `heavy` for agent, `manual` for human.

## Recommended usage

| Context        | Command                       | What runs          |
| -------------- | ----------------------------- | ------------------ |
| CI (default)   | `qed verify --pin`            | `always` only      |
| CI (thorough)  | `qed verify --extended --pin` | `always` + `heavy` |
| Pre-push hooks | `qed verify --auto --pin`     | `always` only      |
| Local dev      | `qed verify`                  | everything         |
| Worker loop    | `qed run spec.toml --pin`     | everything         |

## Exit codes

| Code | Meaning                                                                                        |
| ---- | ---------------------------------------------------------------------------------------------- |
| 0    | Success — all criteria passed                                                                  |
| 1    | Verification failure — one or more criteria failed                                             |
| 2    | Configuration or usage error — bad spec, missing file, unknown command, or integrity violation |

## Error output

Parse errors and usage errors include structured context when available:

```
error: expected '=' after key
 --> spec.toml:3:5
  |
3 | naem = "my-spec"
  |     ^
hint: check for typos in key names
```

Components (all optional except the error line):

- **`error: <message>`** — always present, always to stderr
- **` --> file:line:col`** — when a source location is known
- **Code frame** — numbered source line with caret pointer (TOML and JSON parse errors)
- **`hint: <suggestion>`** — actionable next step

With `--json`, errors produce a structured object:

```json
{
  "error": "expected '=' after key",
  "location": { "file": "spec.toml", "line": 3, "col": 5 },
  "hint": "check for typos in key names"
}
```

## JSON Lines events

`--json-lines` streams one compact JSON object per line. Each has a `type` field. `--json` and `--json-lines` are mutually exclusive.

### Verify mode

| Event        | Fields                                                        |
| ------------ | ------------------------------------------------------------- |
| `spec_start` | `spec`, `criteriaCount`                                       |
| `criterion`  | `description`, `result`, `details`, `exitCode?`, `elapsedMs?` |
| `spec_done`  | `spec`, `passed`                                              |
| `error`      | `message`                                                     |

All objects — including criterion rows — carry a `type` field. The criterion object shape is identical in `--json` and `--json-lines`.

### Worker loop mode

| Event             | Fields                                                                     |
| ----------------- | -------------------------------------------------------------------------- |
| `spec_start`      | `spec`, `mode`, `maxIterations`, `stuckThreshold`                          |
| `iteration_start` | `iteration`                                                                |
| `worker_done`     | `iteration`, `exitCode` or `timedOut`, `elapsedMs`                         |
| `criterion`       | `description`, `result`, `details`, `exitCode?`, `elapsedMs?`, `iteration` |
| `iteration_done`  | `iteration`, `passed`, `failedCount`                                       |
| `loop_done`       | `spec`, `state`, `passed`                                                  |
| `error`           | `message`                                                                  |

## Configuration

All meaningful parameters are configurable at the spec level — defaults are sensible but overridable:

| Parameter            | Default           | Where set                  |
| -------------------- | ----------------- | -------------------------- |
| `maxIterations`      | 10                | Spec file (worker loop)    |
| `stuckThreshold`     | 3                 | Spec file (worker loop)    |
| `timeout` (worker)   | 3600s             | Spec file (`[worker]`)     |
| `timeout` (command)  | 300s              | Spec file (`[[criteria]]`) |
| `timeout` (agent)    | 600s              | Spec file (`[[criteria]]`) |
| `timeout` (property) | 600s              | Spec file (`[[criteria]]`) |
| `model` (agent)      | `claude-opus-4-6` | Spec file (`[[criteria]]`) |
| `workdir`            | `.`               | Spec file (`[worker]`)     |

## Environment variables

### Consumed by qed

| Variable | Purpose                                                  |
| -------- | -------------------------------------------------------- |
| `CI`     | When `true`, auto-enables `--auto` mode if no flag given |
| `TMPDIR` | Temp directory for failure files (falls back to `/tmp`)  |

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

## `.qedignore`

Controls which directories are excluded from recursive spec discovery (`qed verify <dir>`, `qed lock`). Format follows `.gitignore`/`.prettierignore` conventions:

- One pattern per line
- `#` for comments, blank lines ignored
- fnmatch-style globs: `*` (any sequence), `?` (any single char), `[abc]` (class), `[!abc]` (negated class), `[a-z]` (range)
- Prefix a pattern with `!` to negate (un-ignore) — last matching pattern wins

When no `.qedignore` file exists, no directories are excluded.

Example:

```
# Directories to exclude from spec discovery
.lake
.git
archive
wip
scratch
*.draft
!important.draft
```

## Named constants

Not configurable — reasonable defaults hardcoded in the IO shell:

| Constant              | Value      | Location                                         |
| --------------------- | ---------- | ------------------------------------------------ |
| `maxOutputLength`     | 2000 chars | `Verifier.lean` — output truncation (keeps tail) |
| `stderrPreviewLength` | 200 chars  | `WorkerLoop.lean` — stderr preview in terminal   |
