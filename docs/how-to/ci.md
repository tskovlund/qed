# How to add qed to CI

Run `qed verify` in your CI pipeline to check all specs on every push.

## GitHub Actions

```yaml
- name: Verify specs
  run: qed verify
```

This recursively finds all `.spec.json` and `.spec.toml` files in the repository and verifies them. qed exits with code 0 if all criteria pass, 1 if any fail, and 2 on configuration errors.

For JSON output (useful for downstream parsing):

```yaml
- name: Verify specs
  run: qed verify --json
```

## Controlling what runs in CI

Each criterion has a `ci` field that controls when it runs:

```toml
[[criteria]]
description = "Build passes"
verify = { type = "command", run = "make build" }
ci = "always"      # every CI run (default for automatable types)

[[criteria]]
description = "Manual sign-off"
verify = { type = "human", instruction = "Check the UI" }
ci = "manual"      # never in CI (default for human)
```

| Value | When it runs |
|-------|-------------|
| `always` | Every CI run (PRs, pushes, merge queue) |
| `trunk` | Only when the default branch changes |
| `manual` | Only via explicit `qed run` |

## Criteria that require external tools

qed never silently skips verification — if a criterion's tool isn't available (agent binary, proof checker, property testing framework, etc.), the criterion **fails**. This applies to all verification types equally.

To exclude criteria from environments where their tools aren't installed, set `ci = "manual"`:

```toml
[[criteria]]
description = "Code review"
ci = "manual"
verify = { type = "agent", prompt = "Review the implementation." }

[[criteria]]
description = "Termination proof"
ci = "manual"
verify = { type = "proof", prover = "lean4", target = "Proofs.Termination.loop_terminates" }
```

This keeps the criteria in the spec but only runs them via explicit `qed run`, not in CI. To run them in CI, ensure the required tools are installed and any API keys are available as secrets.

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
