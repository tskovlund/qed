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
schedule = "local"         # pre-push and explicit invocation, not CI (default for human)

[[criteria]]
description = "Full agent review"
verify = { type = "agent", prompt = "Review everything." }
schedule = "manual"        # only explicit invocation without flags (default for agent)
```

| Value | When it runs | Excluded by |
|-------|-------------|-------------|
| `always` | Every run (CI, local, explicit) | — |
| `local` | Pre-push and explicit invocation | `--ci` |
| `manual` | Only via explicit invocation without flags | `--ci`, `--local` |

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
