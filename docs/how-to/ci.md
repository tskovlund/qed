# How to add qed to CI

Run `qed verify` in your CI pipeline to check all specs on every push.

## GitHub Actions

```yaml
- name: Verify specs
  run: qed verify --ci
```

The `--ci` flag excludes criteria with `schedule = "manual"` or `schedule = "local"` — only `always` criteria run. This recursively finds all `.spec.json` and `.spec.toml` files in the repository and verifies them. qed exits with code 0 if all criteria pass, 1 if any fail, and 2 on configuration errors.

For JSON output (useful for downstream parsing):

```yaml
- name: Verify specs
  run: qed verify --json
```

## Controlling what runs in CI

Each criterion has a `schedule` field that controls when it runs:

```toml
[[criteria]]
description = "Build passes"
verify = { type = "command", run = "make build" }
schedule = "always"        # every run (default for command/property/proof)

[[criteria]]
description = "Design review"
verify = { type = "human", instruction = "Check the UI" }
# schedule defaults to "manual" for human criteria

[[criteria]]
description = "Full agent review"
verify = { type = "agent", prompt = "Review everything." }
# schedule defaults to "manual" for agent criteria
```

| Value | When it runs | Excluded by | Default for |
|-------|-------------|-------------|-------------|
| `always` | Every run (CI, local, explicit) | — | command, property, proof |
| `local` | Pre-push and explicit invocation | `--ci` | — |
| `manual` | Only via explicit invocation without flags | `--ci`, `--local` | human, agent |

## Criteria that require external tools

qed never silently skips verification — if a criterion's tool isn't available (agent binary, proof checker, property testing framework, etc.), the criterion **fails**. This applies to all verification types equally.

To exclude criteria from CI where their tools aren't installed, set `schedule = "manual"`:

```toml
[[criteria]]
description = "Code review"
schedule = "manual"
verify = { type = "agent", prompt = "Review the implementation." }

[[criteria]]
description = "Termination proof"
schedule = "manual"
verify = { type = "proof", prover = "lean4", target = "Proofs.Termination.loop_terminates" }
```

This keeps the criteria in the spec but only runs them via explicit invocation without flags, not in CI or local mode. To run them in CI, ensure the required tools are installed and any API keys are available as secrets.

Alternatively, use `skip` to disable a criterion entirely (in all environments) with a documented reason:

```toml
[[criteria]]
description = "Exchange rate refresh"
skip = "flaky, investigating #42"
verify = { type = "command", run = "pytest tests/test_refresh.py" }
```

Skipped criteria show `[SKIP]` in output and do not affect the overall pass/fail result.

## Verifying a specific directory

```yaml
- name: Verify specs
  run: qed verify specs/
```

This limits verification to specs in the `specs/` directory and its subdirectories.

## Ensuring manual criteria get validated

Human and agent criteria default to `schedule = "manual"`, which means they are excluded from `--ci` and `--local` (pre-push hooks). This is intentional — human criteria require interactive input, and agent criteria are expensive — but it means they only run during explicit invocation.

To run everything, including manual criteria:

```sh
qed verify specs/
```

No flags means no filtering — all criteria run regardless of schedule.

**Recommended practices:**

- **Before merging structural PRs**, run `qed verify` without flags to validate agent and human criteria. Add this as a PR checklist item.
- **For agent criteria in CI**, consider a scheduled workflow (e.g. nightly or weekly) that runs `qed verify` without flags. This catches drift between scheduled runs. Ensure the agent binary and any API keys are available as CI secrets.
- **Override the default** if a human or agent criterion should run more frequently. Set `schedule = "always"` or `schedule = "local"` explicitly to include it in CI or pre-push hooks.
